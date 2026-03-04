# Rails app

Rails is the system of record and user-facing product. Users sign in with Devise, submit prompts on the dashboard (creating `GenerationJob` records), and can browse the asset library and asset detail pages.

## Prerequisites

- **Ruby** 3.x
- **Bundler** (`gem install bundler`)

## Setup

```bash
bundle install
bundle exec rails db:create   # if using Postgres; not needed for SQLite
bundle exec rails db:migrate
```

## Run

```bash
bundle exec rails s
```

Server listens on **http://localhost:3000**.

## Usage

- **Root (/)** — Redirects to dashboard when signed in, or to sign-in when not.
- **Sign up / Sign in** — Devise routes (e.g. `/users/sign_up`, `/users/sign_in`). After sign-in you are redirected to the dashboard.
- **Dashboard** — Submit a prompt to create a `GenerationJob` (stored in DB; no generation runs yet). Recent jobs are listed.
- **Asset library** — List of your assets (empty until generation is wired).
- **Asset detail** — View metadata, linked job prompt/status, and a download placeholder.

## Database

- **Default:** SQLite (`db/development.sqlite3`). No extra setup.
- **Postgres:** Replace `sqlite3` with `pg` in the Gemfile, update `config/database.yml`, then `rails db:create db:migrate`.

## Customize Devise views

To edit sign-in/sign-up forms and emails:

```bash
bundle exec rails generate devise:views
```

Then edit the generated templates under `app/views/devise/`.

## Port

Default port is 3000. To use another port:

```bash
bundle exec rails s -p 3001
```
