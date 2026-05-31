# Better Notes

Better Notes is an early prototype for an AI-first note-taking app for students.

This first version is intentionally lightweight:

- Start on a home page with class folders.
- Create new class folders.
- Open a class folder to see notes.
- Create or open notes from inside a class folder.
- Draw or write on a full-page blank note.
- Switch between pen and eraser.
- Use AI Lens to select part of the page or scan the full note.
- Choose Check, Hint, or Grade feedback mode.
- Save folders, notes, titles, and drawings in local storage.
- Send AI Lens scans to an OpenAI vision model through a local backend.

## Run it

For the full prototype, including real AI Lens feedback, create a `.env` file:

```txt
OPENAI_API_KEY=your_api_key_here
OPENAI_MODEL=gpt-5-mini
PORT=8080
```

Then run:

```sh
npm start
```

Then visit:

```txt
http://localhost:8080
```

You can still open `index.html` directly for the non-AI parts of the prototype, but AI Lens needs the local server so your API key stays out of browser code.

## Next build steps

- Improve AI Lens selection into a true lasso tool.
- Add PDF import for worksheets and practice tests.
- Move to Flutter or native iPad once the core workflow feels right.
