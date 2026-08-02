import Foundation

extension RepositoryPolicy {
    public enum Ruleset {
        public static func protectedMainPayload(from url: URL) throws -> Data {
            let source = try Data(contentsOf: url)
            guard var object = try JSONSerialization.jsonObject(with: source) as? [String: Any]
            else {
                throw ConfigurationError("protected-main ruleset must be a JSON object")
            }
            guard (object.removeValue(forKey: "schemaVersion") as? Int) == 1 else {
                throw ConfigurationError("unsupported protected-main ruleset schema")
            }
            guard object["name"] as? String == "Institute protected main",
                object["target"] as? String == "branch",
                object["enforcement"] as? String == "active"
            else {
                throw ConfigurationError("protected-main ruleset identity is invalid")
            }
            guard let bypass = object["bypass_actors"] as? [Any], bypass.isEmpty else {
                throw ConfigurationError("protected-main ruleset permits a bypass actor")
            }
            guard let conditions = object["conditions"] as? [String: Any],
                let reference = conditions["ref_name"] as? [String: Any],
                (reference["include"] as? [String]) == ["refs/heads/main"],
                (reference["exclude"] as? [String]) == []
            else {
                throw ConfigurationError("protected-main ruleset must select only main")
            }
            guard let rules = object["rules"] as? [[String: Any]],
                Set(rules.compactMap { $0["type"] as? String }) == [
                    "deletion", "non_fast_forward", "pull_request", "required_status_checks",
                ]
            else {
                throw ConfigurationError(
                    "protected-main ruleset rules differ from the Institute contract"
                )
            }
            guard
                let review = rules.first(where: { $0["type"] as? String == "pull_request" })?[
                    "parameters"
                ] as? [String: Any], review["required_approving_review_count"] as? Int == 1,
                review["dismiss_stale_reviews_on_push"] as? Bool == true,
                review["require_last_push_approval"] as? Bool == true,
                review["required_review_thread_resolution"] as? Bool == true,
                review["require_code_owner_review"] as? Bool == false
            else {
                throw ConfigurationError(
                    "protected-main pull-request transaction differs from the Institute contract"
                )
            }
            guard
                let checks = rules.first(where: {
                    $0["type"] as? String == "required_status_checks"
                })?["parameters"] as? [String: Any],
                checks["strict_required_status_checks_policy"] as? Bool == true,
                checks["do_not_enforce_on_create"] as? Bool == false,
                let required = checks["required_status_checks"] as? [[String: Any]],
                required.count == 1, required.first?["context"] as? String == "ci / ci-ok"
            else {
                throw ConfigurationError(
                    "protected-main status-check transaction differs from the Institute contract"
                )
            }
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
    }
}
