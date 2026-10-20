# Where the docs live

The writing, checking, capture and findings work the same wherever the docs end up. Only the
delivery bead changes. The source is always Markdown articles with frontmatter, plus committed
WebP screenshots, in the repo.

## Recommending one

| The app | Recommend |
| --- | --- |
| Signed-in, several roles, and some readers must not see other roles' docs | **In-app help**, filtered on the server |
| Signed-in, readers want help beside the page they're on | **In-app help** |
| Single audience, or docs are mainly for the team, or no appetite for app changes | **Markdown in the repo** |
| Public product, readers not signed in, or docs have to be indexed by search engines | **Docs site** from the same Markdown |

If the answer to "must some readers never receive another audience's docs?" is yes, then only
in-app help with server-side filtering is honest. Anything sent to the browser can be read, and
that includes a screenshot of an admin screen.

## In-app help

- **Loader**: the server reads `articles/**/*.md` at boot and parses the frontmatter. Invalid
  frontmatter fails loudly: one unquoted `[id]` in YAML once took down a whole library.
- **Filtering on the server**: work out the caller's audience from the same access profile that
  guards the app's API. Filter whole articles by `audiences`, blocks inside an article by
  `<!-- audience: … -->`, and **screenshots**: serve one only if an article the caller can see
  uses it. Remove links to articles the caller can't see, leaving plain text.
- **Endpoints**: a list of articles (metadata for search), one article (the filtered body), and
  one screenshot (bytes, not `sendFile`. Express's `sendFile` returns 404 for any path
  containing a dot-folder).
- **Help page**: client-side search (MiniSearch, for example) over the caller's articles, grouped
  by area, and an article view that fetches screenshots through the API.
- **Help link in the app shell** that opens the articles whose `routes` match the current page.
- **Admin preview**: admins can switch the help page to "what <audience> sees" so they can
  check a page before sending someone to it. While impersonating a user, an admin sees that
  user's help.
- **Tests**: unit tests on the filter for each audience, and the e2e boundary test (see
  `capture-harness.md`).

## Markdown in the repo

- `docs/user/articles/<area>/<slug>.md` and `docs/user/screenshots/`. Screenshots are referenced
  by relative path instead of `shot:`, and links by relative path instead of `help:`.
- A generated or hand-kept `docs/user/README.md` index for each audience, in `order`.
- Audience blocks become a plain callout ("**Admins only:** …"), because there's no filtering.
  Say so in the authoring guide.
- The freshness checks run as a script in the unit gate.

## Docs site

- Build it from the same `articles/` with the site generator the repo already uses, or pick one
  and record why as an epic DECISION.
- If audiences must be kept apart, use one site per audience built from filtered sources. Don't
  hide pages with client-side JavaScript.
- Add a CI build step so a broken link or missing screenshot fails the build.
