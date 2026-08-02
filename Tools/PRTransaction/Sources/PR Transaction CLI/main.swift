import Foundation
import PR_Transaction

enum Main {
    static func main() {
        do {
            print(try PRTransaction.Command.run(Array(CommandLine.arguments.dropFirst())))
        } catch {
            fputs("pr-transaction: \(error)\n", stderr)
            exit(1)
        }
    }
}

Main.main()
