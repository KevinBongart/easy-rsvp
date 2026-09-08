# Dependency audit — 2026-09-08

Generated from `Gemfile.lock` at `38413a5` using bundler-audit 0.9.3 and
ruby-advisory-db commit `e7179ad`. Command:
`RBENV_VERSION=4.0.3 bundle-audit check --update --format json`.

159 raw results reduce to **75 distinct gem/advisory pairs across 22 gems**.
Repeated lockfile platform variants account for duplicates. These are version
range matches, not 75 verified exploitable application paths. The scanner also
includes development/test dependencies and installed Rails components the app
does not load. Vendored Trix/clipboard and Ruby/Node runtimes are outside this audit.

Patch ranges below are the database's reported ranges for each individual
advisory; resolving one row does not guarantee that other rows for that gem are
resolved. Check current upstream releases and compatibility before choosing upgrades.

| Gem | Locked version | Advisory | Reported patched ranges |
| --- | --- | --- | --- |
| actionview | 8.0.2.1 | [CVE-2026-33168](https://github.com/rails/rails/security/advisories/GHSA-v55j-83pf-r9cq) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activestorage | 8.0.2.1 | [CVE-2026-33173](https://github.com/rails/rails/security/advisories/GHSA-qcfx-2mfw-w4cg) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activestorage | 8.0.2.1 | [CVE-2026-33174](https://github.com/rails/rails/security/advisories/GHSA-r46p-8f7g-vvvg) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activestorage | 8.0.2.1 | [CVE-2026-33195](https://github.com/rails/rails/security/advisories/GHSA-9xrj-h377-fr87) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activestorage | 8.0.2.1 | [CVE-2026-33202](https://github.com/rails/rails/security/advisories/GHSA-73f9-jhhh-hr5m) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activestorage | 8.0.2.1 | [CVE-2026-33658](https://github.com/rails/rails/security/advisories/GHSA-p9fm-f462-ggrg) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activestorage | 8.0.2.1 | [CVE-2026-66066](https://www.cve.org/CVERecord/SearchResults?query=CVE-2026-66066) | ~> 7.2.3, >= 7.2.3.2; ~> 8.0.5, >= 8.0.5.1; >= 8.1.3.1 |
| activesupport | 8.0.2.1 | [CVE-2026-33169](https://github.com/rails/rails/security/advisories/GHSA-cg4j-q9v8-6v38) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activesupport | 8.0.2.1 | [CVE-2026-33170](https://github.com/rails/rails/security/advisories/GHSA-89vf-4333-qx8v) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| activesupport | 8.0.2.1 | [CVE-2026-33176](https://github.com/rails/rails/security/advisories/GHSA-2j26-frm8-cmj9) | ~> 7.2.3, >= 7.2.3.1; ~> 8.0.4, >= 8.0.4.1; >= 8.1.2.1 |
| addressable | 2.8.7 | [CVE-2026-35611](https://github.com/sporkmonger/addressable/security/advisories/GHSA-h27x-rffw-24p4) | >= 2.9.0 |
| aws-sdk-s3 | 1.199.0 | [CVE-2025-14762](https://github.com/aws/aws-sdk-ruby/security/advisories/GHSA-2xgq-q749-89fq) | >= 1.208.0 |
| concurrent-ruby | 1.3.5 | [CVE-2026-54904](https://nvd.nist.gov/vuln/detail/CVE-2026-54904) | >= 1.3.7 |
| concurrent-ruby | 1.3.5 | [CVE-2026-54905](https://nvd.nist.gov/vuln/detail/CVE-2026-54905) | >= 1.3.7 |
| concurrent-ruby | 1.3.5 | [CVE-2026-54906](https://www.cve.org/CVERecord/SearchResults?query=CVE-2026-54906) | >= 1.3.7 |
| crass | 1.0.6 | [GHSA-6jxj-px6v-747w](https://github.com/rgrove/crass/security/advisories/GHSA-6jxj-px6v-747w) | >= 1.0.7 |
| crass | 1.0.6 | [GHSA-6wmf-3r64-vcwv](https://github.com/rgrove/crass/security/advisories/GHSA-6wmf-3r64-vcwv) | >= 1.0.7 |
| crass | 1.0.6 | [GHSA-8vfg-2r28-hvhj](https://github.com/rgrove/crass/security/advisories/GHSA-8vfg-2r28-hvhj) | >= 1.0.7 |
| crass | 1.0.6 | [GHSA-wwpr-jff3-395c](https://github.com/rgrove/crass/security/advisories/GHSA-wwpr-jff3-395c) | >= 1.0.7 |
| erb | 5.0.2 | [CVE-2026-41316](https://nvd.nist.gov/vuln/detail/CVE-2026-41316) | ~> 4.0.3.1; ~> 4.0.4.1; ~> 6.0.1.1; >= 6.0.4 |
| json | 2.13.2 | [CVE-2026-54696](https://nvd.nist.gov/vuln/detail/CVE-2026-54696) | >= 2.19.9 |
| loofah | 2.24.1 | [GHSA-9wjq-cp2p-hrgf](https://github.com/flavorjones/loofah/security/advisories/GHSA-9wjq-cp2p-hrgf) | >= 2.25.2 |
| mail | 2.8.1 | [GHSA-mvxr-6m87-mv2q](https://github.com/mikel/mail/security/advisories/GHSA-mvxr-6m87-mv2q) | >= 2.9.1 |
| msgpack | 1.8.0 | [CVE-2026-54522](https://www.cve.org/CVERecord/SearchResults?query=CVE-2026-54522) | >= 1.8.2 |
| net-imap | 0.5.10 | [CVE-2026-42245](https://github.com/ruby/net-imap/security/advisories/GHSA-q2mw-fvj9-vvcw) | ~> 0.4.24; ~> 0.5.14; >= 0.6.4 |
| net-imap | 0.5.10 | [CVE-2026-42246](https://github.com/ruby/net-imap/security/advisories/GHSA-vcgp-9326-pqcp) | ~> 0.3.10; ~> 0.4.24; ~> 0.5.14; >= 0.6.4 |
| net-imap | 0.5.10 | [CVE-2026-42256](https://github.com/ruby/net-imap/security/advisories/GHSA-87pf-fpwv-p7m7) | ~> 0.4.24; ~> 0.5.14; >= 0.6.4 |
| net-imap | 0.5.10 | [CVE-2026-42257](https://github.com/ruby/net-imap/security/advisories/GHSA-hm49-wcqc-g2xg) | ~> 0.4.24; ~> 0.5.14; >= 0.6.4 |
| net-imap | 0.5.10 | [CVE-2026-42258](https://github.com/ruby/net-imap/security/advisories/GHSA-75xq-5h9v-w6px) | ~> 0.4.24; ~> 0.5.14; >= 0.6.4 |
| net-imap | 0.5.10 | [CVE-2026-47240](https://www.cve.org/CVERecord?id=CVE-2026-47240) | ~> 0.5.15; >= 0.6.4.1 |
| net-imap | 0.5.10 | [CVE-2026-47241](https://www.cve.org/CVERecord?id=CVE-2026-47241) | ~> 0.5.15; >= 0.6.4.1 |
| net-imap | 0.5.10 | [CVE-2026-47242](https://www.cve.org/CVERecord?id=CVE-2026-47242) | ~> 0.5.15; >= 0.6.4.1 |
| nokogiri | 1.18.9 | [GHSA-5prr-v3j2-97mh](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-5prr-v3j2-97mh) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-5v8h-3h3q-446p](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-5v8h-3h3q-446p) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-8678-w3jw-xfc2](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-8678-w3jw-xfc2) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-9cv2-cfxc-v4v2](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-9cv2-cfxc-v4v2) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-c4rq-3m3g-8wgx](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-c4rq-3m3g-8wgx) | >= 1.19.3 |
| nokogiri | 1.18.9 | [GHSA-g9g8-vgvw-g3vf](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-g9g8-vgvw-g3vf) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-p67v-3w7g-wjg7](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-p67v-3w7g-wjg7) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-phwj-rprq-35pp](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-phwj-rprq-35pp) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-v2fc-qm4h-8hqv](https://nvd.nist.gov/vuln/detail/CVE-2026-79771) | >= 1.19.3 |
| nokogiri | 1.18.9 | [GHSA-wfpw-mmfh-qq69](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-wfpw-mmfh-qq69) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-wjv4-x9w8-wm3h](https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-wjv4-x9w8-wm3h) | >= 1.19.4 |
| nokogiri | 1.18.9 | [GHSA-wx95-c6cv-8532](https://nvd.nist.gov/vuln/detail/CVE-2026-79772) | >= 1.19.1 |
| puma | 7.0.2 | [CVE-2026-47736](https://www.cve.org/CVERecord?id=CVE-2026-47736) | ~> 7.2.1; >= 8.0.2 |
| puma | 7.0.2 | [CVE-2026-47737](https://www.cve.org/CVERecord/SearchResults?query=CVE-2026-47737) | ~> 7.2.1; >= 8.0.2 |
| rack | 3.2.1 | [CVE-2025-61770](https://github.com/rack/rack/security/advisories/GHSA-p543-xpfm-54cp) | ~> 2.2.19; ~> 3.1.17; >= 3.2.2 |
| rack | 3.2.1 | [CVE-2025-61771](https://github.com/rack/rack/security/advisories/GHSA-w9pc-fmgc-vxvw) | ~> 2.2.19; ~> 3.1.17; >= 3.2.2 |
| rack | 3.2.1 | [CVE-2025-61772](https://github.com/rack/rack/security/advisories/GHSA-wpv5-97wm-hp9c) | ~> 2.2.19; ~> 3.1.17; >= 3.2.2 |
| rack | 3.2.1 | [CVE-2025-61780](https://github.com/rack/rack/security/advisories/GHSA-r657-rxjc-j557) | ~> 2.2.20; ~> 3.1.18; >= 3.2.3 |
| rack | 3.2.1 | [CVE-2025-61919](https://github.com/rack/rack/security/advisories/GHSA-6xw4-3v39-52mm) | ~> 2.2.20; ~> 3.1.18; >= 3.2.3 |
| rack | 3.2.1 | [CVE-2026-22860](https://github.com/rack/rack/security/advisories/GHSA-mxw3-3hh2-x2mh) | ~> 2.2.22; ~> 3.1.20; >= 3.2.5 |
| rack | 3.2.1 | [CVE-2026-25500](https://github.com/rack/rack/security/advisories/GHSA-whrj-4476-wvmp) | ~> 2.2.22; ~> 3.1.20; >= 3.2.5 |
| rack | 3.2.1 | [CVE-2026-26961](https://github.com/rack/rack/security/advisories/GHSA-vgpv-f759-9wx3) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-26962](https://github.com/rack/rack/security/advisories/GHSA-rx22-g9mx-qrhv) | >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-32762](https://github.com/rack/rack/security/advisories/GHSA-qfgr-crr9-7r49) | ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34230](https://github.com/rack/rack/security/advisories/GHSA-v569-hp3g-36wr) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34763](https://github.com/rack/rack/security/advisories/GHSA-7mqq-6cf9-v2qp) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34785](https://github.com/rack/rack/security/advisories/GHSA-h2jq-g4cq-5ppq) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34786](https://github.com/rack/rack/security/advisories/GHSA-q4qf-9j86-f5mh) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34826](https://github.com/rack/rack/security/advisories/GHSA-x8cg-fq8g-mxfx) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34827](https://github.com/rack/rack/security/advisories/GHSA-v6x5-cg8r-vv6x) | ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34829](https://github.com/rack/rack/security/advisories/GHSA-8vqr-qjwx-82mw) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34830](https://github.com/rack/rack/security/advisories/GHSA-qv7j-4883-hwh7) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34831](https://github.com/rack/rack/security/advisories/GHSA-q2ww-5357-x388) | ~> 2.2.23; ~> 3.1.21; >= 3.2.6 |
| rack | 3.2.1 | [CVE-2026-34835](https://github.com/rack/rack/security/advisories/GHSA-g2pf-xv49-m2h5) | ~> 3.1.21; >= 3.2.6 |
| rack-session | 2.1.1 | [CVE-2026-39324](https://github.com/rack/rack-session/security/advisories/GHSA-33qg-7wpp-89cq) | >= 2.1.2 |
| rails-html-sanitizer | 1.6.2 | [GHSA-cj75-f6xr-r4g7](https://github.com/rails/rails-html-sanitizer/security/advisories/GHSA-cj75-f6xr-r4g7) | >= 1.7.1 |
| ruby-lsp | 0.26.1 | [CVE-2026-34060](https://github.com/Shopify/ruby-lsp/security/advisories/GHSA-c4r5-fxqw-vh93) | >= 0.26.9 |
| rubyzip | 2.4.1 | [CVE-2026-85396](https://nvd.nist.gov/vuln/detail/CVE-2026-85396) | >= 3.4.0 |
| uri | 1.0.3 | [CVE-2025-61594](https://github.com/advisories/GHSA-j4pr-3wm6-xx2r) | ~> 0.12.5; ~> 0.13.3; >= 1.0.4 |
| websocket-driver | 0.8.0 | [CVE-2026-54463](https://www.cve.org/CVERecord/SearchResults?query=CVE-2026-54463) | >= 0.8.1 |
| websocket-driver | 0.8.0 | [CVE-2026-54464](https://www.cve.org/CVERecord/SearchResults?query=CVE-2026-54464) | >= 0.8.1 |
| websocket-driver | 0.8.0 | [CVE-2026-54465](https://www.cve.org/CVERecord/SearchResults?query=CVE-2026-54465) | >= 0.8.1 |
| websocket-driver | 0.8.0 | [CVE-2026-61666](https://www.cve.org/CVERecord?id=CVE-2026-61666) | >= 0.8.2 |
