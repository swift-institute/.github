def unmeasured_of: map(select(.parked | not) | select(.resolve == "clone-failed"));
def failing_of: map(select(.parked | not) | select(
    .resolve == "not-a-package" or .resolve == "clone-failed" | not) | select(
    .resolve != "pass" or .build != "pass" or (.test != "pass" and .test != "skip")));
def keys_of: map("\(.repository) \(.platform)");
map(. + {parked: (.repository as $r | $parked | index($r) != null)}) as $all
| ($all | map(select(.platform as $p | $advisory | index($p) == null))) as $results
| ($results | map(select(.parked | not) | select(.resolve == "clone-failed"))) as $unmeasured
| ($results | map(select(.parked | not) | select(
    .resolve == "not-a-package" or .resolve == "clone-failed" | not) | select(
    .resolve != "pass" or .build != "pass" or (.test != "pass" and .test != "skip")))) as $failing
| ([$shards[] | .repositories | split(" ")[] | select(length > 0) | "\(.) linux", "\(.) macos"]
    - ($results | map("\(.repository) \(.platform)"))) as $missing
| {date: $date, run: $run, partial: $partial,
   provenance: {linux: {image: $image, provisioning: "apt -dev packages derived from the .linkedLibrary declarations in each graph (.github/actions/install-system-deps/install.sh); listed per row in provisioned; a bare stock image is not certified"},
                macos: {xcode: $xcode, provisioning: "none"},
                provisioned: ($results | map(select(.provisioned // "" | length > 0) | .provisioned | split(" ")[]) | unique)},
   complete: (($partial | not) and ($results | length) > 0 and ($missing | length) == 0 and ($unmeasured | length) == 0),
   green: (($partial | not) and ($results | length) > 0 and ($failing | length) == 0 and ($missing | length) == 0 and ($unmeasured | length) == 0),
   counts: {results: ($results | length), failing: ($failing | length),
            unmeasured: ($unmeasured | length),
            parked: ($results | map(select(.parked)) | length), missing: ($missing | length)},
   missing: $missing,
   unmeasured: ($unmeasured | map("\(.repository) \(.platform)")),
   failing: ($failing | map("\(.repository) \(.platform)")),
   causes: ($failing | group_by(.cause // "") | map({cause: (.[0].cause // ""), count: length}) | sort_by(-.count)),
   unmeasuredCauses: ($unmeasured | group_by(.cause // "") | map({cause: (.[0].cause // ""), count: length}) | sort_by(-.count)),
   advisory: ($advisory | map(. as $p | {key: $p, value: ($all | map(select(.platform == $p))) | {
       counts: {results: length, failing: (failing_of | length), unmeasured: (unmeasured_of | length),
                parked: (map(select(.parked)) | length)},
       failing: (failing_of | keys_of), unmeasured: (unmeasured_of | keys_of)}}) | from_entries),
   results: $all}
