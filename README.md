## Rebar3 licence scraper

- based on rebar3 tree plugin
- uses the ruby gem [licensee](https://github.com/benbalter/licensee) to analyse the project's dependencies' licenses
  note licensee must be installed with `gem install licensee`

add the plugin to your rebar.config

```
    {rebar_license_scan, {git, "https://github.com/monkeygroover/rebar3-license-scan.git", {branch, "master"}}}

```

run

`rebar3 licence-scan`

