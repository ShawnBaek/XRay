"""Bounded LLDB commands for XRay's DEBUG-only Objective-C bridge."""

from __future__ import print_function

import os
import shlex
import subprocess
import tempfile

import lldb


_BRIDGE_CLASS = "XRayDebugBridge"
_EXPRESSION_TIMEOUT_US = 5 * 1000 * 1000
_MAX_CAPTURE_BYTES = 64 * 1024 * 1024
_MAX_TEXT_CHARS = 1024 * 1024
_USAGE = "xray show|hide|tree|capture [--output PATH] [--open]"


def _fail(result, message):
    result.SetError("xray: " + message)


def _expression_options():
    options = lldb.SBExpressionOptions()
    options.SetLanguage(lldb.eLanguageTypeObjC_plus_plus)
    options.SetIgnoreBreakpoints(True)
    options.SetUnwindOnError(True)
    options.SetTryAllThreads(False)
    options.SetStopOthers(True)
    options.SetTimeoutInMicroSeconds(_EXPRESSION_TIMEOUT_US)
    return options


def _expression_error(value):
    if value.IsValid() and value.GetError().Success():
        return None
    error = value.GetError()
    detail = error.GetCString() if error.IsValid() else None
    return detail or "the debugger could not evaluate the expression"


def _find_main_frame(process):
    queue_matches = []
    for thread in process:
        if not thread.IsValid() or thread.GetNumFrames() == 0:
            continue
        if thread.GetQueueName() == "com.apple.main-thread":
            queue_matches.append(thread)

    if len(queue_matches) != 1:
        if not queue_matches:
            return None, (
                "could not safely identify the main thread. Stop where LLDB can "
                "identify the com.apple.main-thread queue, then retry."
            )
        return None, "main-thread identification was ambiguous; no expression was run."

    frame = queue_matches[0].GetFrameAtIndex(0)
    if not frame.IsValid():
        return None, "the identified main thread has no valid frame."
    return frame, None


def _context(debugger, exe_ctx, result):
    target = exe_ctx.GetTarget() if exe_ctx else debugger.GetSelectedTarget()
    if not target.IsValid():
        _fail(result, "no valid target is selected.")
        return None

    process = exe_ctx.GetProcess() if exe_ctx else target.GetProcess()
    if not process.IsValid() or process.GetProcessID() in (0, lldb.LLDB_INVALID_PROCESS_ID):
        _fail(result, "no process is attached. Attach or launch under LLDB and pause it first.")
        return None
    if process.GetState() != lldb.eStateStopped:
        _fail(result, "the attached process must be stopped; it will not be paused or resumed automatically.")
        return None

    frame, error = _find_main_frame(process)
    if error:
        _fail(result, error)
        return None
    return process, frame


def _evaluate(frame, expression):
    return frame.EvaluateExpression(expression, _expression_options())


def _require_bridge(frame, result):
    value = _evaluate(
        frame,
        '(BOOL)((Class)NSClassFromString(@"%s") != Nil)' % _BRIDGE_CLASS,
    )
    error = _expression_error(value)
    if error:
        _fail(result, "could not look up %s: %s" % (_BRIDGE_CLASS, error))
        return False
    if value.GetValueAsUnsigned(0) == 0:
        _fail(
            result,
            "%s is unavailable. Link XRay into the app's Debug build and see docs/LLDB.md#install-xray-in-the-debug-build."
            % _BRIDGE_CLASS,
        )
        return False
    return True


def _call_string(frame, selector, result):
    value = _evaluate(
        frame,
        '(id)[(id)(Class)NSClassFromString(@"%s") %s]'
        % (_BRIDGE_CLASS, selector),
    )
    error = _expression_error(value)
    if error:
        _fail(result, "%s failed: %s" % (selector, error))
        return None
    description = value.GetObjectDescription()
    if description is None:
        _fail(result, "%s returned no status text." % selector)
        return None
    return description


def _last_error(frame):
    value = _evaluate(
        frame,
        '(id)[(id)(Class)NSClassFromString(@"%s") lastError]' % _BRIDGE_CLASS,
    )
    if _expression_error(value):
        return None
    return value.GetObjectDescription()


def _parse_capture(arguments):
    output = None
    should_open = False
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument == "--open":
            if should_open:
                raise ValueError("--open may be specified only once")
            should_open = True
        elif argument == "--output":
            if output is not None:
                raise ValueError("--output may be specified only once")
            index += 1
            if index >= len(arguments):
                raise ValueError("--output requires a path")
            output = arguments[index]
        elif argument.startswith("--output="):
            if output is not None:
                raise ValueError("--output may be specified only once")
            output = argument[len("--output=") :]
            if not output:
                raise ValueError("--output requires a path")
        else:
            raise ValueError("unknown capture argument: %s" % argument)
        index += 1
    return output, should_open


def _capture(process, frame, output, should_open, result):
    retained = _evaluate(
        frame,
        '(uintptr_t)[(id)[(id)(Class)NSClassFromString(@"%s") capturePNG] retain]'
        % _BRIDGE_CLASS,
    )
    error = _expression_error(retained)
    if error:
        _fail(result, "capturePNG failed: %s" % error)
        return

    object_address = retained.GetValueAsUnsigned(0)
    if object_address == 0:
        detail = _last_error(frame) or "capturePNG returned nil without an error description."
        _fail(result, detail)
        return

    try:
        length_value = _evaluate(
            frame, "(unsigned long long)[(id)0x%x length]" % object_address
        )
        error = _expression_error(length_value)
        if error:
            _fail(result, "could not read capture length: %s" % error)
            return
        length = length_value.GetValueAsUnsigned(0)
        if length == 0:
            _fail(result, "capturePNG returned empty data.")
            return
        if length > _MAX_CAPTURE_BYTES:
            _fail(
                result,
                "capture is %d bytes; the adapter limit is %d bytes."
                % (length, _MAX_CAPTURE_BYTES),
            )
            return

        bytes_value = _evaluate(
            frame, "(uintptr_t)[(id)0x%x bytes]" % object_address
        )
        error = _expression_error(bytes_value)
        if error:
            _fail(result, "could not locate capture bytes: %s" % error)
            return
        bytes_address = bytes_value.GetValueAsUnsigned(0)
        if bytes_address == 0:
            _fail(result, "capturePNG returned a null bytes pointer.")
            return

        memory_error = lldb.SBError()
        data = process.ReadMemory(bytes_address, length, memory_error)
        if not memory_error.Success():
            _fail(result, "could not transfer PNG data: %s" % memory_error.GetCString())
            return
        if isinstance(data, str):
            data = data.encode("latin-1")
        if len(data) != length:
            _fail(result, "PNG transfer was incomplete (%d of %d bytes)." % (len(data), length))
            return
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            _fail(result, "capture data does not have a PNG signature.")
            return

        path = _output_path(output, result)
        if path is None:
            return
        try:
            mode = "wb" if output is None else "xb"
            with open(path, mode) as stream:
                stream.write(data)
        except (IOError, OSError) as write_error:
            _fail(result, "could not write %s: %s" % (path, write_error))
            return

        result.PutCString("XRay capture written to %s" % path)
        if should_open:
            try:
                completed = subprocess.run(
                    ["/usr/bin/open", path],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                    check=False,
                    text=True,
                    timeout=5,
                )
            except (OSError, ValueError, subprocess.TimeoutExpired) as open_error:
                _fail(result, "capture was written, but could not be opened: %s" % open_error)
                return
            if completed.returncode != 0:
                detail = completed.stderr.strip() or "open exited with status %d" % completed.returncode
                _fail(result, "capture was written, but could not be opened: %s" % detail)
    finally:
        _evaluate(frame, "(void)[(id)0x%x release]" % object_address)


def _output_path(output, result):
    if output is None:
        descriptor, path = tempfile.mkstemp(prefix="xray-", suffix=".png")
        os.close(descriptor)
        return path

    path = os.path.abspath(os.path.expanduser(output))
    if os.path.exists(path):
        _fail(result, "output already exists: %s" % path)
        return None
    parent = os.path.dirname(path)
    if not os.path.isdir(parent):
        _fail(result, "output directory does not exist: %s" % parent)
        return None
    return path


def xray(debugger, command, exe_ctx, result, internal_dict):
    """Run an XRay bridge command in a stopped process."""
    del internal_dict
    try:
        arguments = shlex.split(command)
    except ValueError as parse_error:
        _fail(result, "could not parse arguments: %s. Usage: %s" % (parse_error, _USAGE))
        return

    if not arguments or arguments[0] in ("help", "-h", "--help"):
        result.PutCString(_USAGE)
        return

    operation = arguments.pop(0)
    if operation not in ("show", "hide", "tree", "capture"):
        _fail(result, "unknown command %r. Usage: %s" % (operation, _USAGE))
        return
    if operation != "capture" and arguments:
        _fail(result, "%s takes no arguments. Usage: %s" % (operation, _USAGE))
        return

    output = None
    should_open = False
    if operation == "capture":
        try:
            output, should_open = _parse_capture(arguments)
        except ValueError as parse_error:
            _fail(result, "%s. Usage: %s" % (parse_error, _USAGE))
            return

    context = _context(debugger, exe_ctx, result)
    if context is None:
        return
    process, frame = context
    if not _require_bridge(frame, result):
        return

    if operation == "capture":
        _capture(process, frame, output, should_open, result)
        return

    selector = {"show": "show", "hide": "hide", "tree": "hierarchyDescription"}[operation]
    message = _call_string(frame, selector, result)
    if message is not None:
        if len(message) > _MAX_TEXT_CHARS:
            _fail(
                result,
                "%s returned more than %d characters; output was suppressed."
                % (selector, _MAX_TEXT_CHARS),
            )
            return
        result.PutCString(message)
        if operation in ("show", "hide"):
            result.PutCString("The process remains stopped; continue it to see the onscreen change.")


def __lldb_init_module(debugger, internal_dict):
    del internal_dict
    debugger.HandleCommand(
        "command script add -o -f %s.xray -h 'Inspect XRay in a stopped UIKit process' xray"
        % __name__
    )
    print("XRay LLDB commands installed. Run 'xray help'.")
