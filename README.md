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

## Run it

Open `index.html` in a browser, or run a local static server from this folder:

```sh
python3 -m http.server 8080
```

Then visit:

```txt
http://localhost:8080
```

## Next build steps

- Add page saving with local storage.
- Improve AI Lens selection into a true lasso tool.
- Connect the feedback panel to a real AI vision/model endpoint.
- Add PDF import for worksheets and practice tests.
- Move to Flutter or native iPad once the core workflow feels right.
