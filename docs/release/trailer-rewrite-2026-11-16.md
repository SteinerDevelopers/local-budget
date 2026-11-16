# Co-author trailer history rewrite — 2026-11-16 (owner-approved)

**What.** Two early commits (ci: sideload-rail signing, Mon 03:18Z; build: R8
keeps, 05:20Z) carried `Co-Authored-By` trailers naming an AI-tool vendor's
public bot address — spontaneously reproduced by the authoring model from
training data, not by any tool in the pipeline (no such CLI exists on any
fleet host; proven via reflog + filesystem search). GitHub resolves that
address to the vendor account and surfaced it in the repo's contributor
graph, which misrepresents a local-model-only project.

**Action (owner GO, 2026-11-16 ~11:25C).** Message-surgical rewrite via
`git filter-repo --message-callback` (drops trailer lines; also removed a
quoted literal in a later commit body so no parser can re-attribute).
Two force-pushes under the merge-gate doc's documented rule-replacement
break-glass (window ~40 s total; protection read back after each: push =
No one, merge = Maintainers, force = false).

**Proof.** Every branch tip tree byte-identical to the pre-rewrite oracle
clone (per-ref `rev-parse <ref>^{tree}` hash equality against a pristine
mirror clone captured before any write); 0 residual trailer/address
matches across ALL reachable commits of all refs locally, corroborated by
a live API scan of the newest 100 `main` commits;
tag `kit/v0.1.0-beta-2026-11-09` untouched (points below the blast radius;
kit identity unaffected).

**Blast radius.** 34 commits got new shas (2 carriers + descendants).
Old shas quoted in docs/playbook from 2026-11-15 21:18Z onward are
historical aliases; the map below is the translation table. GitHub may
serve stale commit pages / contributor graphs until ref-GC and graph
rebuild (order of hours–a day).

## old -> new map

```
03a126ae979aeb65628ea9329a4e2deb60423618 -> 87e8541d5865aa0a47da9b244f95daa86a3e02a5 | build(release): ML Kit ServiceLoader keep — device-proven on SL219A
03b51d119ba80d9da883db41f76ea89a1b9dee36 -> 7a7925acc9627479efa63960b9231a6b2579678a | ci(mirror): auto-sync public GitHub mirror on green main
03d48f6bc4486cb0358ca5081c1c72875befeed5 -> 30a778a926716896aa2d1c40bcb6a4e2690fd6f3 | Merge branch 'r8-memory-012' into 'main'
0dac08bb5b32c49e944946f681b00e3d4c149a71 -> 78a7fe4dea258a1dec874afb255345a57a18ba3d | ci(package-apk-free): ship the sideload rail release-signed
1a48f3c9d57146c4ef57e135e72144f011451f13 -> 643007c76d2d407ddfef075eb724f1544e8350ac | ci(mirror): needs e2e-android explicitly — the needs-less ladder starves (measured 929)
21579a4f68deab35be3c5c2adfb0f8752ef96542 -> f7658c139e804ed2d1d05e0d3d9e08945aef44cf | (branch/MR-ref only)
21f6d6b73010b21ade680bfe903bb3de7b07aea1 -> 1ca9c25cbee4508a282b0ed48965cfd143a63206 | Merge branch 'kit-mapping-artifact' into 'main'
22796b84ed9fca29107ed5354d6081c2b25f0e62 -> b3bccc385b125f0e9f776456a8d564ad269e7343 | (branch/MR-ref only)
39677f2331f5d8857263f5aa2fd83dc950417875 -> 5f2d306dccf71c27848eca9ba957340188f24634 | Merge branch 'package-apk-release-signed' into 'main'
397a834511d3dcad1af32fb4dafbb8b7e93ac81f -> 6353d4208aa03da9a9723dda285d732aeb4cce5f | (branch/MR-ref only)
60a9ab5753de92de8ac69c4a1cbfc8c8a6ef6d5e -> 7c5bd5e7e6712b12a78f1c9ee45fa066aa08ebfd | ci(mirror): never materialize off protected refs — restore merge-button
61e2af97622af03ac30c9c4c832e45edcad5d44c -> a75670bb8a81b0183cfbc0e953b1669dc498ae3b | (branch/MR-ref only)
63d7f6649aca873aae5a18def5d3e5a6ce26f4d4 -> 6c33a364e01d42f89da86568a1c4c89341d2e6b4 | (branch/MR-ref only)
64ac186f87ebaa9a1c5b9ec01b64fbb08b68a389 -> 69c92357fbb5c6d9c0d2a88f1f15797e2d4e5761 | build(release): R8 minify+shrink ON with named ML Kit dontwarns
674b90c1051cb6006430c27087e4ff6af6a7581f -> 146141431d0fc18086875d11e93821cb16270d6b | Merge branch 'mirror-auto-main' into 'main'
6e324ee4350068b38b85d5dad3199624e3f31f6b -> cb045447b3d4edff2cd4db0050452b2967ddad81 | ci(kit): ship R8 mapping with every free AAB
7955ba6e39b948c770f146affd1d9c7987f3f283 -> d8c9a969812ab1e8c77bfde8ac9fde179bc9c9d4 | (branch/MR-ref only)
7985075290e0bade58e1e03ab351570820bcd4e2 -> 37b5d7816262e5f8d10227b657264973e350707e | Merge branch 'mirror-needs-e2e' into 'main'
837e24ecc85a9ceb4a7a88ecb1661ef5fa3501c0 -> 84202958335be3105075870ebe9a9e5a0fc568fc | perf(capture): release the OCR recognizer after every document
8974a19753d182afee525ceffa379631a70f6c25 -> 7863f72a42cd8abdd92765d5334f76b4ec356987 | chore(release): 0.1.2+3 — changelog for the scorecard line
926d8711bc7ed50705ecd05fba822709257504b3 -> f014d43e121f793c402f95eccc062a24307cdd77 | Merge branch 'readme-install-link' into 'main'
97b72427de57c1e16e7d9da329ae198fd9b54d93 -> 367af5d4f74e00c3233019e38e16ce2f92be154b | Merge branch 'drop-contrib-section' into 'main'
9de85a36b2802a257b0100acdf80d63041548ecf -> a46a54363a1f4fa084a26cc40ab2a86bfa2c5ec7 | docs(readme): surface install channels on the landing page
9e13192491fe10e771ad883c676031f115aeaee4 -> 9fe49dc8537c3a1f424594d7255ba0f5c1f3d48c | docs(readme): name both rails in install heading; drop misleading 'latest'
9ebfc45b5f795991e3238ece07be43739f596111 -> f4d2bce68824d0fb9820f136a42e086d6bf59970 | docs(contributing): withdraw public contribution section per owner; record AI-trailer provenance
ac4a98e8bade73d288c78ce4a212ef0193a28ce0 -> c827c51ee9355206a3ce1c0ef7cee07728a2dcae | (branch/MR-ref only)
b7fd65d43cf72468e8f10468efb46ee947c639f6 -> 838e665787eb701870af1afe27580eed5118c497 | (branch/MR-ref only)
c94d292bd775949c3288d31a347e6cc70e642445 -> 367af5d4f74e00c3233019e38e16ce2f92be154b | Merge branch 'drop-contrib-section' into 'main'
cd5aadeb5801a49fa06771baf0844b5a4656e3e5 -> caad87607a38532c42291b441d50aa4cd3cd2312 | (branch/MR-ref only)
d9d6e3ef897d4f576668283424713ea890062b48 -> e07457e4528c513da8a1c4cc0056f7c3bfa76b91 | (branch/MR-ref only)
de73140461f3ae3f73b2c1aa62194aa1718a0b5b -> 5329c077921588a2f871d86759d7431237736dc2 | chore(ci): report-only co-author-trailer guard in commit-lint
ea5c86f7c8f73863515efd3690415b3eba06e14b -> 924efa4557120c315723675b0bfc922a2e885969 | Merge branch 'readme-rail-honesty' into 'main'
f36537f7cf054f4741479a15425bc0628b0367c4 -> f4d2bce68824d0fb9820f136a42e086d6bf59970 | docs(contributing): withdraw public contribution section per owner; record AI-trailer provenance
fee638225e98f8335405e766145521089e455204 -> d7fab2d7c5f102b55e194bfa95c7ff70866d804a | Merge branch 'r8-keeps-012' into 'main'
```
