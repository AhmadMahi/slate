<div align="center">

# Slate

**An open-source, AI-powered OneNote alternative with a glassmorphism design and a freeform infinite canvas.**

*Your notes. Your format. Every platform.*

`Freeform canvas` · `Handwriting & math` · `Quizzes & mind maps` · `Presentations` · `Ask AI` · `Open file format` · `Local-first` · `macOS · Windows · Linux`

</div>

---

> **Usable today, and actively developed.** Slate is a real, working desktop app:
> a freeform canvas, ink, math, live Markdown, an open file format, sync through
> any folder you already have, a OneNote importer that handles real notebooks,
> and a growing set of teaching tools — quizzes, mind maps, slide presentations
> and an AI assistant — wrapped in a glassmorphism interface. Your notes always
> live on your own machine in an open, documented format that stays readable
> without Slate, so nothing is locked in.

## Contents

- [Install](#install)
- [What is Slate?](#what-is-slate)
- [Features and how to use them](#features-and-how-to-use-them)
  - [The canvas and your notebooks](#the-canvas-and-your-notebooks)
  - [Writing: text, Markdown, math, code, tables](#writing-text-markdown-math-code-tables)
  - [Drawing and ink](#drawing-and-ink)
  - [Page backgrounds and themes](#page-backgrounds-and-themes)
  - [Insert: everything you can add to a page](#insert-everything-you-can-add-to-a-page)
  - [Quizzes](#quizzes)
  - [Mind maps](#mind-maps)
  - [Presentations](#presentations)
  - [AI features](#ai-features)
  - [Ask AI](#ask-ai)
  - [Sync and backup](#sync-and-backup)
  - [Importing from OneNote, PDF and Markdown](#importing-from-onenote-pdf-and-markdown)
- [Building from source](#building-from-source)
- [Guiding principles](#guiding-principles)
- [License](#license)
- [Contributing](#contributing)
- [Credits](#credits)

## Install

Grab the latest build from the [Releases page](https://github.com/AhmadMahi/slate/releases).

| | Download | Then |
|---|---|---|
| **macOS** | `slate-*-macos-universal.dmg` | Open it, drag **Slate** to Applications. |
| **Windows** | `slate-*-windows-x64-setup.exe` | Run it. Installs for your user only, so it never asks for an administrator password. (Prefer no installer? The `.zip` is the same build.) |
| **Linux** | build from source | See [Building from source](#building-from-source). |

Your notes are written to your own machine in an open, documented format. There
is no account, and nothing is uploaded anywhere unless you turn on sync or
connect your own AI key.

### Your operating system will warn you. Here is why, honestly.

Slate is not code-signed. Certificates cost a few hundred dollars a year per
platform, and while the project is this young that money buys nothing a user
would notice. The warnings do not mean the software is unsafe, only that we have
not paid to tell your OS who we are.

- **Windows**: *"Windows protected your PC"*, click **More info** then **Run anyway**.
- **macOS**: *"Slate is damaged and can't be opened"*, after copying to
  Applications run `xattr -cr /Applications/Slate.app` once.

## What is Slate?

Microsoft OneNote is, for many people, the best freeform note-taking tool ever
made: an infinite canvas where you click anywhere, drop a text box, draw with a
pen, and write complex equations, all inside a familiar notebook, section and
page structure. Nothing open has quite matched it.

But OneNote traps your notes in a proprietary format, defaults to a mandatory
cloud, has no native Linux client, gates features behind subscriptions, and has
ignored years of requests for Markdown, an open format, and backlinks.

Slate matches OneNote's experience with open technology, fixes its structural
failings by construction, and adds a layer of teaching and AI tools on top:

- 🎨 **A genuine freeform infinite canvas** — click anywhere, place anything, pan and zoom, free-form or snap-to-grid.
- 🗂️ **The notebook hierarchy you know** — notebooks, section groups, sections, pages, subpages.
- ✍️ **Rich text with inline-rendered Markdown** — formatting appears where you type it.
- ➗ **Beautiful math entry** — type linearly and watch it build into 2-D notation.
- 🖊️ **First-class pen and handwriting** — low-latency, pressure-sensitive ink.
- ❓ **Quizzes**, 🧠 **mind maps** and 📽️ **slide presentations** built into the page.
- 🤖 **Bring-your-own-key AI** — generate quizzes, mind maps, code and page templates, grow a branch, turn a chat answer into a summary/quiz/mind map, and chat with an assistant, using your own OpenAI or OpenRouter key.
- 📦 **An open, documented file format** — local-first, no lock-in, readable without us.
- ☁️ **Cloud-optional sync** — through any folder you already sync, or a GitHub repo.

## Features and how to use them

### The canvas and your notebooks

- **Structure.** A **notebook** holds **section groups** and **sections**, which
  hold **pages** and **subpages** — the OneNote hierarchy. Create them from the
  sidebar; the **+** by a section adds a page, and **Section** adds a section.
- **The Home dashboard** shows every notebook as a card with real page/section
  counts and a Recent row to jump back in.
- **Move around the canvas.** Scroll or two-finger drag to pan; `Ctrl`/`Cmd` +
  scroll to zoom. The floating controls in the page's top-right corner do zoom,
  **fit to width**, and **focus mode** (the page edge-to-edge with just a glass
  tool palette).
- **Place anything anywhere.** Click empty canvas to start a text box, or use
  **Insert**. Blocks are free-form by default and can snap to a grid.
- **Select everything.** `Cmd`/`Ctrl` + **A** selects every block on the page
  (when you are not typing in a box — there it still selects the text), so you
  can move, copy or delete the whole page at once.

### Writing: text, Markdown, math, code, tables

- **Text with live Markdown.** Type `**bold**`, `# heading`, `- list`, `[[page
  link]]` and it renders in place as you type.
- **Math.** Insert → Equation, then type linearly (e.g. `int_0^1 x^2 dx`) and it
  builds into 2-D notation. A **Graph** button on the equation draws its curve; a
  **Substitute** shows the value at a point.
- **Code.** Insert → Code for a monospace block with syntax highlighting; pick a
  language (or let it auto-detect), and `sql`/`js` blocks can **run** on this
  device. **Write or rewrite it with AI** — the sparkle button beside Copy turns
  a plain-language description into code, or rewrites the code already there to
  an instruction (respecting the chosen language). **Drag its corner or bottom**
  to give it a fixed height; longer code then scrolls inside the box.
- **Tables.** Insert → Table, or import a CSV into one.
- **Word count / reading time** is shown per page in the status bar.

### Drawing and ink

Switch to the pen (the toolbar pencil, or press **P**) to draw anywhere.

- **Pen and highlighter** — pressure-sensitive, low-latency ink; pick a colour
  and size from the draw toolbar.
- **Rectangle tool** — press **R** (or the square button) and drag corner to
  corner. Rectangles draw with **true square corners**, not rounded.
- **Arrow tool** — drag to draw a straight arrow.
- **Auto-shapes** — draw a rough shape and hold; it snaps to a clean shape.
  While holding, drag up/down to resize; release to make it draggable; one more
  click places it and returns to the pen.
- **Eraser** — press **E**; or marquee-select ink and delete it.
- **Insert Space** — from the focus-mode palette, push content down to make room.

### Page backgrounds and themes

- **Paper patterns** — Blank, Grid, Dots, Ruled, with adjustable spacing.
- **Backgrounds** — the signature **ambient** paper plus more ambient variants
  (sunset, ocean, forest, dusk, aurora) and solid papers (Sage, Sky, Blush,
  Charcoal, Midnight, and more).
- **Themes** — System, Light or Dark, with a soft accent colour that washes the
  whole app. Set per-app in **Settings → Appearance**; defaults for new pages in
  **Settings → Default page settings**.

### Insert: everything you can add to a page

**Insert** (the toolbar, or right-click the canvas) offers, in one list:
Text box, Equation, Code, Table, **Board** (a Trello-style task board), **Quiz**,
**Mind map**, Picture, **PDF slides**, **Presentation**, Video, File, Flashcard,
Page link, **Page window** (a live embed of another page), and Template.

### Quizzes

A multiple-choice quiz that lives on the page: name at the top, one question at a
time, four options, per-question **Submit** revealing green/red and an
explanation, and a final score.

**Three ways to fill a quiz** (Insert → Quiz):

1. **Upload a file** — a CSV or Excel file, one row per question: *question, four
   options, correct answer (1-4, A-D, or the exact option text), explanation*
   (1-20 questions). A **Download template** button gives you the shape.
2. **Paste rows** — paste the same rows straight into the box.
3. **Auto generate with AI** — type a topic and a count and let your connected
   AI provider write the questions. They are validated exactly like an uploaded
   file before they land.

The quiz block is draggable and resizable.

### Mind maps

An auto-laid-out, left-to-right tree you build by typing (Insert → Mind map).

- **Build it with the keyboard.** **Enter** adds a sibling branch; **Ctrl/Cmd+C**
  adds a child (Tab also adds a child); **Ctrl/Cmd+Shift+C** outdents.
- **Collapse and expand.** Each branch has a fold knob. **Collapse all** folds
  the map to its main branches so you can reveal one branch at a time while
  teaching; **Expand all** reopens everything.
- **Colour.** Give any node a solid or translucent colour, or use **Auto colour
  branches** to tint each branch its own hue in one click.
- **Generate with AI.** Describe a map and the model drafts it (as a Markdown
  outline, which becomes the tree).
- **Grow a branch with AI.** Select a node and click its sparkle badge; the model
  suggests sub-topics for exactly that node, given its place in the tree, and
  appends them.
- **Import.** Turn any Markdown outline (`.md`) into a map.
- The block resizes both wider and taller, and scrolling/panning over the map
  moves the map, not the page beneath it.

### Presentations

Page through a slide deck on the page, the way you would run it while teaching
(Insert → Presentation).

- **Import** a **PDF** deck. (To use a PowerPoint, export it to PDF first.)
- **Page through it** one slide at a time: Back/Next, the arrow keys, and a slide
  counter, in a soft rounded slide frame.
- **Present full screen** — a large, distraction-free presenter: arrow keys, tap
  the left/right half of the screen, `Esc` to leave.
- The deck is stored once as a content-addressed file and pages render on demand,
  so a big deck costs the PDF's own size, once.

### AI features

Slate can use a cloud AI with **your own API key** — nothing is sent anywhere
until you connect one, and the key is stored in your operating system's own
password storage (Keychain / Credential Manager / libsecret), never in a file or
a notebook.

**Connect a provider:** Settings → Connections → **AI provider**.

1. Choose **OpenAI** or **OpenRouter**.
2. Paste your **API key**.
3. Type a **model name** (for example `gpt-4o-mini`, or `openai/gpt-4o-mini` on
   OpenRouter).
4. Click **Connect** — Slate makes one tiny test call and shows a green tick when
   it works. A running **token-usage** total is shown there, with a reset.

**Provider in use.** Keep keys for both OpenAI and OpenRouter if you like; the
**Provider in use** control at the top of the dialog chooses which one every AI
feature calls. Switch it any time — only a connected provider can be chosen.

**Custom instructions per feature.** Under **AI instructions**, every place Slate
uses AI has its own editable instruction — Ask AI, the quiz generator, the
mind-map generator, grow-a-branch, code generation, summaries, and templates.
Reset any of them to normal, or write your own to change how that feature behaves
(its tone, level or language). The required output format for each is added
automatically, so a custom instruction can never break generation.

This powers the quiz generator, the mind-map generator, **code generation**,
**AI templates**, the **Ask AI** answer actions and the chat. It is separate from
**AI access** (the MCP server, which lets external tools like Claude read your
notes) — both can be on at once.

**Generate a template with AI.** Insert → Template → **Generate with AI**:
describe a page layout ("a weekly lesson plan with objectives, activities and
homework") and the model drafts the sections, laid out below anything already on
the page.

### Ask AI

A small chat for quick questions while you work.

- Turn it on in **Settings → Connections → Ask AI**; a chat bubble appears at the
  bottom-right of the page.
- Ask a question, get an answer, using your connected provider. Answers are not
  saved to the notebook.
- **Do something with an answer.** Each answer has a row of actions (also on
  right-click): **Copy**, or turn it straight into a block on the page —
  **Insert as summary** (a text block), **Insert as quiz**, or **Insert as mind
  map**. Slate generates the block from the answer and drops it below your
  content.
- **Steer its style.** In the AI provider settings, the **Ask AI** instruction
  lets you set the tone/subject/language — for example, *"You are a patient tutor
  for high-school biology; use simple analogies and end with a quick check
  question."*

### Sync and backup

Slate is local-first; sync is optional and needs no Slate account.

- **Folder sync.** Point a notebook at any folder your device already syncs
  (Google Drive, OneDrive, Dropbox, iCloud Drive, Syncthing, a NAS…). Slate's
  storage is an append-only, one-writer-per-device log, so two devices editing
  different pages merge cleanly with no duplicate files.
- **GitHub sync.** Connect a GitHub account once (Settings → Connections →
  Sync), then back a notebook with a repository. Once connected, notes sync
  **automatically and incrementally** in the background — after a short pause in
  typing, on a periodic safety-net timer during long sessions, and on close —
  so it only ever sends what changed.
- **Pick a repo when you create a notebook.** With GitHub connected, making a
  new notebook offers **Create new repo** or **Choose an existing repo** right
  after you name it, so the notebook is backed from the start.
- **Push a page to the repo as PDF.** In a page's **Export** menu (when the
  notebook is connected), **Push this page to the repo (PDF)** uploads just that
  page's PDF into a `Whiteboards/<section>/<page>.pdf` folder in the same repo —
  one click while teaching, no Save-as, no browser. It is manual, and
  re-pushing a session updates the same file. This is separate from notes sync:
  the PDF goes straight to the repo through GitHub's API and does not touch the
  notebook's own sync.
- **Mirrors.** Keep one-way backup copies of a notebook.

Set these up in **Settings → Connections → Sync**.

### Importing from OneNote, PDF and Markdown

- **OneNote.** Import real `.one` notebooks, including ink and images.
- **PDF.** Bring a PDF in as annotatable slides, one page per slide, or as a
  card — or as a **Presentation** (above).
- **Markdown.** Turn a Markdown outline into a **mind map**.

## Building from source

Slate is a Flutter desktop app with an optional Rust core.

```bash
cd app
flutter pub get
flutter run -d macos     # or: -d windows, -d linux
```

Full build and packaging notes are in [`app/README.md`](app/README.md), and what
is and isn't verified is tracked honestly in [TESTING.md](TESTING.md).

## Guiding principles

1. **Your data is yours** — an open format, documented and versioned from day one.
2. **Local-first, cloud-optional** — fully usable offline, no account required.
3. **The canvas is sacred** — freeform placement, fast startup and responsive ink come first.
4. **Interpret, don't interrupt** — formatting happens where you type it.
5. **Bring your own AI** — AI is opt-in, with your own key, and never required to use the app.
6. **Open by construction** — an open license, a published format spec, an extensible core.

## License

Three tiers, mapped in full in [LICENSING.md](LICENSING.md):

- **[AGPL-3.0-or-later](LICENSE)** — the application. Fork it, self-host it, modify it; improvements stay open, including for hosted forks.
- **[Apache-2.0](rust/onote_core/LICENSE)** — `onote_core`, the `.onote` reader/writer, hashing and importers.
- **[CC0-1.0](docs/specs/LICENSE)** — the file-format specification. Implement it freely, no attribution required.

Contributions are inbound = outbound with a
[DCO](https://developercertificate.org/) sign-off (`git commit -s`) and no CLA.

## Contributing

Ideas, critiques and expertise — especially on cross-platform ink, rich-text
editing, CRDTs and math input — are very welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Slate is built on **[Openote](https://github.com/icmric/openote)** by
[icmric](https://github.com/icmric). The freeform canvas, the open `.onote` file
format, the OneNote importer and the native Rust core are the original project's
work, and Slate would not exist without it. Slate, released under the same
AGPL-3.0 license, builds a new interface and a wider feature set — the AI tools,
quizzes, mind maps and presentations — on that foundation. Huge thanks to the
original author.

---

<div align="center">
<sub>Slate is not affiliated with or endorsed by Microsoft. "OneNote" and "Microsoft" are trademarks of Microsoft Corporation, referenced here for comparison and interoperability only.</sub>
</div>

---

<sub>Slate is a fork of, and takes its foundation and inspiration from, **[Openote](https://github.com/icmric/openote)** by icmric — with thanks and full credit to the original project.</sub>
