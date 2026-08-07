import Foundation
import Repository_Policy

extension Main {
    /// `repository-policy draft-metadata --repository <owner/name>
    /// [--spec-titles <path>] [--package-description <text>]
    /// [--date <YYYY-MM-DD>]`
    ///
    /// Prints the bootstrap `.github/metadata.yaml` draft to stdout — the
    /// decision half of the retired `generate-metadata.sh`. The clone,
    /// commit, and pull request stay in `generate-metadata.yml`: they are
    /// plumbing over a token, and keeping them out is what lets the
    /// classification be tested without one.
    static func draftMetadata(_ arguments: [String]) throws {
        var repository: String?
        var specTitles: String?
        var packageDescription = ""
        var date: String?
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--repository": repository = iterator.next()
            case "--spec-titles": specTitles = iterator.next()
            case "--package-description": packageDescription = iterator.next() ?? ""
            case "--date": date = iterator.next()
            default:
                throw RepositoryPolicy.ConfigurationError(
                    "unknown draft-metadata argument \(argument)")
            }
        }
        guard let repository else {
            throw RepositoryPolicy.ConfigurationError("draft-metadata requires --repository")
        }
        var titles = Repository.Policy.Metadata.Draft.Titles()
        if let specTitles {
            guard let data = FileManager.default.contents(atPath: specTitles) else {
                throw RepositoryPolicy.ConfigurationError("spec titles not found: \(specTitles)")
            }
            titles = .init(parsing: String(decoding: data, as: UTF8.self))
        }
        let draft = try Repository.Policy.Metadata.Draft(
            target: repository, titles: titles, packageDescription: packageDescription)
        let render = Repository.Policy.Metadata.Draft.Render(generatedOn: date ?? Self.today)
        print(render(draft), terminator: "")
    }

    /// Today in UTC, `YYYY-MM-DD` — the header stamp the retired script
    /// took from `date -u +%Y-%m-%d`. Overridable by `--date` so a test
    /// (and a re-run of the same wave) renders the same bytes.
    private static var today: String {
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC") ?? .gmt, from: Date())
        return String(
            format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0,
            components.day ?? 0)
    }
}
