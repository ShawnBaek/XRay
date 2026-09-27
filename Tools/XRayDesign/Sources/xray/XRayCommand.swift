import Foundation
import XRayDesignCore

@main
struct XRayCommand {
    @MainActor static func main() async {
        do {
            let message = try await DesignTool.run(arguments: Array(CommandLine.arguments.dropFirst()))
            print(message)
        } catch {
            FileHandle.standardError.write(Data("xray: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
