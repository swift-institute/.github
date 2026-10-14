def unmeasured_of: map(select(.parked | not) | select(.resolve == "clone-failed"));
def failing_of: map(select(.parked | not) | select(
    .resolve == "not-a-package" or .resolve == "clone-failed" or .resolve == "excluded" | not) | select(
    .resolve != "pass" or .build != "pass" or (.test != "pass" and .test != "skip")));
def keys_of: map("\(.repository) \(.platform)");
def expected($platforms): [$shards[] | .repositories | split(" ")[] | select(length > 0) | select(. as $r | $parked | index($r) == null) | . as $r | $platforms[] | "\($r) \(.)"];
def missing_cause: "no result: the shard produced no row for this repository";
map(. + {parked: (.repository as $r | $parked | index($r) != null)}) as $all
| ($all | map(select(.platform as $p | $advisory | index($p) == null))) as $results
| ($results | unmeasured_of) as $unmeasured
| ($results | failing_of) as $failing
| (expected(["linux", "macos"]) - ($results | keys_of)) as $missing
| {date: $date, run: $run, partial: $partial,
   provenance: {linux: {image: $image, provisioning: "apt -dev packages derived from the .linkedLibrary declarations in each graph (.github/actions/install-system-deps/install.sh); listed per row in provisioned; a bare stock image is not certified"},
                macos: {xcode: $xcode, provisioning: "none"},
                provisioned: ($results | map(select(.provisioned // "" | length > 0) | .provisioned | split(" ")[]) | unique)},
   complete: (($partial | not) and ($results | length) > 0 and ($missing | length) == 0 and ($unmeasured | length) == 0),
   green: (($partial | not) and ($results | length) > 0 and ($failing | length) == 0 and ($missing | length) == 0 and ($unmeasured | length) == 0),
   counts: {results: ($results | length), failing: ($failing | length),
            unmeasured: (($unmeasured | length) + ($missing | length)),
            parked: ($results | map(select(.parked)) | length), missing: ($missing | length)},
   missing: $missing,
   unmeasured: (($unmeasured | keys_of) + $missing),
   failing: ($failing | keys_of),
   causes: ($failing | group_by(.cause // "") | map({cause: (.[0].cause // ""), count: length}) | sort_by(-.count)),
   unmeasuredCauses: (($unmeasured | group_by(.cause // "") | map({cause: (.[0].cause // ""), count: length}))
       + (if ($missing | length) > 0 then [{cause: missing_cause, count: ($missing | length)}] else [] end)
       | sort_by(-.count)),
   advisory: ($advisory | map(. as $p | ($all | map(select(.platform == $p))) as $rows
       | (expected([$p]) - ($rows | keys_of)) as $absent
       | {key: $p, value: {
           counts: {results: ($rows | length), failing: ($rows | failing_of | length),
                    unmeasured: (($rows | unmeasured_of | length) + ($absent | length)),
                    excluded: ($rows | map(select(.resolve == "excluded")) | length),
                    parked: ($rows | map(select(.parked)) | length), missing: ($absent | length)},
           failing: ($rows | failing_of | keys_of),
           unmeasured: (($rows | unmeasured_of | keys_of) + $absent),
           missing: $absent}}) | from_entries),
   results: $all}
