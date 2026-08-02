import Foundation
import PR_Transaction

enum Main {
    static func main() {
        do {
            print(try PRTransaction.Command.run(Array(CommandLine.arguments.dropFirst())))
        } catch {
            FileHandle.standardError.write(Data("pr-transaction: \(error)\n".utf8))
            exit(1)
        }
    }
}

Main.main()
