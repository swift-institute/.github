map(. + {parked: (.repository as $r | $parked | index($r) != null)}) as $results
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
   results: $results}
