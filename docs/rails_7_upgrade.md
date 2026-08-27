# Rails 6.1 → 7.2 Upgrade Plan (single_cell_portal_core)

## Context

The app is pinned to `rails '6.1.7.9'` (Gemfile:7) with `config.load_defaults 6.1`
(config/application.rb:25), on Ruby 3.4.8. The goal is to move to Rails 7.2 following
the official upgrade guide (https://guides.rubyonrails.org/upgrading_ruby_on_rails.html),
covering the 6.1→7.0, 7.0→7.1, and 7.1→7.2 transitions.

**Important architectural fact that changes the scope of the standard guide:** this app
uses **Mongoid**, not ActiveRecord (`active_record/railtie` is commented out in
config/application.rb). That eliminates most of the guide's ActiveRecord-specific
sections (schema.rb dumps, encryption digest changes, SQLite strict strings,
`alias_attribute` on AR models, migrations). The real risk surface here is: Zeitwerk
under stricter defaults, the Sprockets/jQuery-UJS asset stack, and a cluster of
Rails-adjacent gems (Devise, Mongoid ecosystem, secure_headers, rack-mini-profiler,
Sentry) that all need major-version bumps in lockstep with Rails.

No `config/credentials.yml.enc`/`master.key` exists; the app uses legacy
`config/secrets.yml`, which is actually dead code today because
`config/initializers/secret_key_base.rb` monkey-patches
`Rails::Application#secret_key_base` to always return `ENV['SECRET_KEY_BASE']`.

## Recommended approach: incremental version stepping, not a direct 6.1→7.2 jump

Do 6.1 → 7.0 → 7.1 → 7.2, each as its own commit/PR-sized step: bump the `rails` gem
constraint, run `bin/rails app:update`, bump `config.load_defaults`, resolve the
generated `new_framework_defaults_7_x.rb` file, run the full test suite, and only then
move to the next minor. This matches how the guide itself is written (one section per
hop) and makes it possible to bisect regressions to a specific hop instead of one giant
diff. Each hop below lists what actually applies to this codebase (the rest of each
guide section is ActiveRecord/Webpacker-only and can be skipped).

---

## Step 1: Rails 6.1 → 7.0

**Gem/config changes**
- Bump `gem 'rails'` to the latest `~> 7.0` patch, `bundle update rails` (and let
  transitive actionpack/activejob/etc. move together).
- `config.load_defaults 7.0` in config/application.rb:25.
- Run `bin/rails app:update`, diff the generated `config/initializers/new_framework_defaults_7_0.rb`
  against current behavior, then delete/consolidate the existing
  `config/initializers/new_framework_defaults_6_1.rb` (its two active lines —
  `action_controller.urlsafe_csrf_tokens` and
  `action_view.form_with_generates_remote_forms = false` — become baked-in defaults).
- Sprockets is no longer a default Rails dependency as of 7.0 — confirm `sprockets-rails`
  and `sprockets` stay explicit Gemfile/lockfile entries (they already are used via
  `require "sprockets/railtie"` in config/application.rb:15, so this is just a
  verification step, not a new addition).
- Cache format: set `config.active_support.cache_format_version = 7.0` only after
  confirming no old Rails 6.1 processes are still reading the cache during deploy
  (rolling-deploy consideration for the ops/deploy process, flag for the deploy runbook
  rather than a code change).
- Digest algorithm change (SHA1→SHA256 for key generation) — mostly relevant to
  ActiveRecord encryption (not used here) and session/cookie signing. Since
  `secret_key_base.rb` already forces `ENV['SECRET_KEY_BASE']` and session store is a
  plain cookie store (config/initializers/session_store.rb), the main risk is existing
  user sessions being invalidated on deploy — acceptable/expected for this kind of
  upgrade, just call it out in the release notes.

**Code changes required**
- `app/controllers/studies_controller.rb:91` — `@study.update_attributes(initialized: true)`.
  This is a Mongoid document so `update_attributes` still resolves via Mongoid's own
  alias (not the removed ActiveRecord one), but normalize it to `@study.update(initialized: true)`
  for clarity/future-proofing.
- `test/models/ingest_job_test.rb:57,70,75` — same normalization,
  `update_attributes!` → `update!`.
- `config/initializers/minitest_rails.rb` — drop the permanently-true
  `if ActionPack::VERSION::STRING >= "5.2.0"` guard; confirm `minitest-rails` gem still
  works against Rails 7's `Rails::TestUnit`.
- Zeitwerk: `config.autoload_paths << Rails.root.join('lib')` (config/application.rb:37)
  — spot-checked already; all `lib/*.rb` files match Zeitwerk naming. No classic-loader
  remnants (`require_dependency`, `config.autoloader =`) exist anywhere in the repo, so
  this hop's mandatory-Zeitwerk requirement is already satisfied. Just re-run
  `bin/rails zeitwerk:check` after the bump to confirm.
- `button_to` default verb change (persisted AR objects switch to `patch`) — does not
  apply since there are no ActiveRecord objects; Mongoid documents aren't affected by
  this Rails helper behavior change, but grep `button_to` usages in views as a quick
  sanity check since the helper logic keys off `persisted?`, which Mongoid documents do
  implement.

---

## Step 2: Rails 7.0 → 7.1

**Gem/config changes**
- Bump `gem 'rails'` to latest `~> 7.1`.
- `config.load_defaults 7.1`; resolve the new `new_framework_defaults_7_1.rb`.
- Secret key file rename for dev/test (`tmp/development_secret.txt` →
  `tmp/local_secret.txt`) — low risk here since `secret_key_base.rb` overrides this
  entirely via `ENV['SECRET_KEY_BASE']`, but note it in case that override is ever
  removed.
- `config.autoload_lib(ignore: %w(...))` — replace the manual
  `config.autoload_paths << Rails.root.join('lib')` (config/application.rb:37) with the
  new `config.autoload_lib` API, explicitly ignoring any non-Ruby subdirectories
  (`lib/tasks`, `lib/assets` already contain no `.rb` files per the audit, but list them
  in `ignore:` for clarity/safety).
- `config.action_dispatch.show_exceptions` boolean → `:all` / `:rescuable` / `:none`.
  This app has a **custom `config.exceptions_app` lambda**
  (config/application.rb:47-53) routing to `Api::V1::ExceptionsController` /
  `ExceptionsController` — explicitly test this against the new enum values in test/dev
  environments once `load_defaults 7.1` changes the default.
- `Rails.logger` becomes an `ActiveSupport::BroadcastLogger` — check
  `config/environments/development.rb`'s custom `ActionMailer::Base.register_interceptor`
  and any other code that assumes `Rails.logger` is a plain `Logger` instance (grep for
  `Rails.logger.instance_of?` / direct `Logger` class checks — none surfaced in the
  scans so far, but worth a final grep before shipping this hop).

**Code changes required**
- None specific to app code beyond the `config.autoload_lib` migration above; this hop
  is mostly config-only for a Mongoid app with no ActiveStorage/SQLite usage.

---

## Step 3: Rails 7.1 → 7.2

**Gem/config changes**
- Bump `gem 'rails'` to latest `7.2.x`.
- `config.load_defaults 7.2`; resolve `new_framework_defaults_7_2.rb`.
- `alias_attribute` behavior change is ActiveRecord-only — not applicable (no
  `alias_attribute` calls found in Mongoid models per the scan).
- Active Job: "all tests now respect `config.active_job.queue_adapter`" — check
  `config/environments/test.rb` for an explicit queue adapter setting and audit any
  tests written assuming `TestAdapter` behavior while a different adapter (e.g.
  `delayed_job`) is configured. Given `delayed_job`/`delayed_job_mongoid` are the
  production queue backend, confirm test env explicitly sets
  `config.active_job.queue_adapter = :test` if that's the intended test behavior.

---

## Gem compatibility bumps required (cuts across all three hops)

Do these as part of the `bundle update` at each hop, verifying CHANGELOGs for the gem's
Rails-7.x support point before locking:

| Gem | Current | Target (latest as of research) | Note |
|---|---|---|---|
| rails | 6.1.7.9 | 7.2.x | core bump |
| mongoid | 7.5.1 | 9.1.0 (latest) — pick the oldest 8.x/9.x release that documents Rails 7.x support | major jump, review Mongoid's own upgrade notes for 7.x/8.x/9.x independent of Rails |
| mongoid-history | 0.8.3 | check for a maintained fork/newer release; low-activity gem, biggest compatibility risk in the Mongoid stack | verify against target Mongoid version, not just Rails |
| mongoid-encrypted-fields | 2.0.0 | verify against target Mongoid | |
| mongoid_rails_migrations | 1.4.0 | verify against target Mongoid | |
| carrierwave-mongoid | 1.3.0 | verify against target Mongoid | |
| devise | 4.8.0 | 5.0.4 (latest) | major bump; re-check `config/initializers/devise.rb` (`devise/orm/mongoid`, omniauth config) and the `DeviseSignOutPatch` `to_prepare` hook in development.rb:137-139 against Devise 5's controller internals |
| omniauth-google-oauth2 / omniauth-rails_csrf_protection | 1.2.2 / 1.0.0 | confirm current majors still resolve alongside Devise 5 + Rails 7.2 | |
| delayed_job / delayed_job_mongoid | 4.1.10 / 2.3.1 | verify ActiveJob/Railtie hook compatibility | low-activity gem, test job enqueue/run end-to-end after upgrade |
| secure_headers | 6.3.2 | 7.3.0 (latest) | major bump; re-verify the CSP config in `config/initializers/content_security_policy.rb` still applies correctly, and check Rack 3 compatibility if Rails 7.2's resolved Rack version moves to 3.x |
| sentry-ruby | 5.23.0 | check latest 5.x/6.x for Rails 7.2 notes | no `sentry-rails` gem currently in Gemfile — Sentry has no Rails-specific instrumentation wired in; out of scope to add, but note if instrumentation gaps matter |
| rack-mini-profiler | 2.3.3 | 5.0.0 (latest) | major bump; only used in dev/test group, verify Rack 3 support if applicable |
| rack-brotli | 1.1.0 | verify Rack 3 compatibility (config.middleware.use Rack::Brotli, config/application.rb:29) | |
| vite_rails | 3.0.6 | 3.11.1 (latest) | verify Rails 7.2 Railtie/asset-helper compatibility |
| sass-rails, coffee-rails, jquery-rails, jquery-datatables-rails, jquery-fileupload-rails, bootstrap-sass, font-awesome-sass, nested_form, will_paginate-bootstrap-style | various | these are all legacy Sprockets-era gems, several installed from unmaintained git forks | not blocked by Rails 7.2 itself (Sprockets stays supported), but flag as a follow-on modernization since `vite_rails` is already present suggesting partial migration off Sprockets is a longer-term goal — **out of scope for this upgrade**, just confirm they still `bundle install`/function |
| minitest-rails | 6.1.0 | verify against Rails 7.2's `Rails::TestUnit` | pairs with the `minitest_rails.rb` initializer cleanup above |
| rubocop-rails | 2.10.1 | bump alongside Rails so cop definitions reflect 7.2 best practices (avoids stale false positives/negatives) | |
| brakeman | 5.0.1 | bump to latest for accurate Rails 7.2-aware security scanning | |

---

## High-risk / manual-regression items (not blocking upgrade, but must be tested)

1. **UJS-driven AJAX (`remote: true` / `format.js`)** — 40 views use `remote: true`,
   21 `format.js` responders across 5 controllers (`studies_controller.rb`,
   `site_controller.rb`, `admin_configurations_controller.rb`,
   `application_controller.rb`, `profiles_controller.rb`). This keeps working under
   7.2 as long as `jquery-rails`/`jquery_ujs` stays required in
   `app/assets/javascripts/application.js:16` and Sprockets remains active — Rails 7
   didn't remove this, but it's no longer a first-class default. Full manual regression
   pass over every affected form/link after the upgrade completes.
2. **`config/initializers/field_with_errors.rb`** — monkey-patches
   `ActionView::Base.field_error_proc` with custom Nokogiri HTML wrapping. Re-verify
   against Rails 7.2's `ActionView::Base` (API has been stable historically, low risk,
   but exercise every form).
3. **`config/initializers/secret_key_base.rb`** — reopens `Rails::Application#secret_key_base`.
   Confirm the method signature is unchanged in 7.2 (expected to be fine) and that
   sessions/CSRF tokens still validate post-upgrade.
4. **Custom `config.exceptions_app`** (config/application.rb:47-53) — depends on the
   private `env['action_dispatch.original_path']` Rack env key and on
   `ActionController::RoutingError` handling in `app/lib/request_utils.rb:247`. Retest
   404/500 pages for both the `api/v1` and non-API paths, especially interacting with
   the Step 2 `show_exceptions` enum change.
5. **`DeviseSignOutPatch`** included via `config.to_prepare` in
   `config/environments/development.rb:137-139` — must be re-verified against
   Devise 5's `RegistrationsController`.
6. **Duplicate/near-duplicate environment files** (`production.rb`, `staging.rb`,
   `pentest.rb` are almost byte-identical) — not a Rails-version issue, but since all
   three need the same `config.load_defaults`/cache-format edits three times, consider
   flagging for consolidation while already touching these files (optional, not
   required for the upgrade itself).

---

## Verification plan

- After each hop (7.0, 7.1, 7.2): `bundle install`, `bin/rails zeitwerk:check`,
  `bin/rails app:update` diff review, then run the full test suite
  (`bin/rails test` / whatever the project's CI test command is) and `brakeman`.
- Manually exercise: sign-in/sign-up/sign-out (Devise + Google OAuth), study
  creation/update flows that use `format.js`/`remote: true` (studies, profiles, admin
  configurations, site controller endpoints), file upload via CarrierWave, background
  job enqueue/run via Delayed Job, CSP headers present via `secure_headers` (check
  browser console for CSP violations), Sentry error reporting still fires, and the
  custom 404/500 exception pages for both API and non-API routes.
- Confirm `config/secrets.yml` remains safely removable (or explicitly leave/remove it
  as a separate decision) — no code depends on `Rails.application.secrets`.
