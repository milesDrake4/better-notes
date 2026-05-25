const homeView = document.querySelector("#homeView");
const classView = document.querySelector("#classView");
const noteView = document.querySelector("#noteView");
const folderForm = document.querySelector("#folderForm");
const folderName = document.querySelector("#folderName");
const folderGrid = document.querySelector("#folderGrid");
const classBackHome = document.querySelector("#classBackHome");
const classTitle = document.querySelector("#classTitle");
const newNoteFromClass = document.querySelector("#newNoteFromClass");
const notesGrid = document.querySelector("#notesGrid");
const backClass = document.querySelector("#backClass");
const folderCrumb = document.querySelector("#folderCrumb");
const noteTitle = document.querySelector("#noteTitle");
const canvas = document.querySelector("#noteCanvas");
const canvasShell = document.querySelector(".canvas-shell");
const selectionBox = document.querySelector("#selectionBox");
const ctx = canvas.getContext("2d");
const penSize = document.querySelector("#penSize");
const clearCanvas = document.querySelector("#clearCanvas");
const toolButtons = document.querySelectorAll("[data-tool]");
const modeButtons = document.querySelectorAll("[data-mode]");
const aiPanel = document.querySelector("#aiPanel");
const lensStatus = document.querySelector("#lensStatus");
const scanSelection = document.querySelector("#scanSelection");
const scanPage = document.querySelector("#scanPage");
const feedback = document.querySelector("#feedback");
const questionInput = document.querySelector("#questionInput");

function makeId() {
  return crypto.randomUUID ? crypto.randomUUID() : `id-${Date.now()}-${Math.random()}`;
}

function escapeHtml(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

const folders = [
  {
    id: makeId(),
    name: "Calculus",
    notes: [
      { id: makeId(), title: "Implicit differentiation", date: "Today", image: null },
      { id: makeId(), title: "Practice test review", date: "Yesterday", image: null },
    ],
  },
  {
    id: makeId(),
    name: "Chemistry",
    notes: [{ id: makeId(), title: "Stoichiometry worksheet", date: "Mon", image: null }],
  },
  {
    id: makeId(),
    name: "English",
    notes: [{ id: makeId(), title: "Essay evidence map", date: "Fri", image: null }],
  },
];

let isDrawing = false;
let isSelecting = false;
let activeTool = "pen";
let activeMode = "check";
let lastPoint = null;
let selectionStart = null;
let hasSelection = false;
let currentFolderId = folders[0].id;
let currentNoteId = null;

function currentFolder() {
  return folders.find((folder) => folder.id === currentFolderId);
}

function currentNote() {
  const folder = currentFolder();
  return folder?.notes.find((note) => note.id === currentNoteId);
}

function showView(view) {
  homeView.classList.toggle("hidden", view !== "home");
  classView.classList.toggle("hidden", view !== "class");
  noteView.classList.toggle("hidden", view !== "note");
}

function renderFolders() {
  folderGrid.innerHTML = folders
    .map((folder) => {
      const noteWord = folder.notes.length === 1 ? "note" : "notes";
      return `
        <article class="folder-card">
          <div class="folder-tab"></div>
          <div>
            <h3>${escapeHtml(folder.name)}</h3>
            <p>${folder.notes.length} ${noteWord}</p>
          </div>
          <div class="card-actions">
            <button type="button" data-open-folder="${folder.id}">Open</button>
            <button class="strong-action" type="button" data-new-note="${folder.id}">New note</button>
          </div>
        </article>
      `;
    })
    .join("");
}

function renderNotes() {
  const folder = currentFolder();
  classTitle.textContent = folder.name;

  if (folder.notes.length === 0) {
    notesGrid.innerHTML = `
      <section class="empty-state">
        <h3>No notes yet</h3>
        <p>Create a blank note for this class and start writing.</p>
      </section>
    `;
    return;
  }

  notesGrid.innerHTML = folder.notes
    .map(
      (note) => `
        <article class="note-card">
          <div class="note-preview"></div>
          <div>
            <h3>${escapeHtml(note.title)}</h3>
            <p>${escapeHtml(note.date)}</p>
          </div>
          <div class="card-actions">
            <button class="strong-action" type="button" data-open-note="${note.id}">Open note</button>
          </div>
        </article>
      `,
    )
    .join("");
}

function resetCanvas() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  hideSelection();
}

function saveCurrentNoteImage() {
  const note = currentNote();
  if (!note) return;

  note.title = noteTitle.value.trim() || "Untitled note";
  note.image = canvas.toDataURL("image/png");
}

function loadNoteImage(note) {
  resetCanvas();
  if (!note.image) return;

  const image = new Image();
  image.addEventListener("load", () => {
    ctx.drawImage(image, 0, 0, canvas.width, canvas.height);
  });
  image.src = note.image;
}

function openFolder(folderId) {
  saveCurrentNoteImage();
  currentFolderId = folderId;
  renderNotes();
  showView("class");
}

function createNote(folderId) {
  saveCurrentNoteImage();
  currentFolderId = folderId;
  const folder = currentFolder();
  const note = {
    id: makeId(),
    title: "Untitled note",
    date: "Just now",
    image: null,
  };

  folder.notes.unshift(note);
  openNote(note.id);
}

function openNote(noteId) {
  currentNoteId = noteId;
  const folder = currentFolder();
  const note = currentNote();

  folderCrumb.textContent = folder.name;
  noteTitle.value = note.title;
  setActiveTool("pen");
  aiPanel.classList.add("closed");
  feedback.innerHTML = `
    <h3>Ready</h3>
    <p>Use AI Lens to select handwritten work and get feedback without leaving the note.</p>
  `;
  loadNoteImage(note);
  showView("note");
}

function goToClass() {
  saveCurrentNoteImage();
  renderNotes();
  showView("class");
}

function canvasPoint(event) {
  const rect = canvas.getBoundingClientRect();
  const scaleX = canvas.width / rect.width;
  const scaleY = canvas.height / rect.height;

  return {
    x: (event.clientX - rect.left) * scaleX,
    y: (event.clientY - rect.top) * scaleY,
  };
}

function shellPoint(event) {
  const rect = canvasShell.getBoundingClientRect();
  return {
    x: event.clientX - rect.left,
    y: event.clientY - rect.top,
  };
}

function beginSelection(event) {
  isSelecting = true;
  hasSelection = false;
  selectionStart = shellPoint(event);
  selectionBox.classList.remove("hidden");
  updateSelectionBox(selectionStart, selectionStart);
  lensStatus.textContent = "Drag around the part of the page you want BetterNotes to inspect.";
}

function updateSelectionBox(start, end) {
  const left = Math.min(start.x, end.x);
  const top = Math.min(start.y, end.y);
  const width = Math.abs(start.x - end.x);
  const height = Math.abs(start.y - end.y);

  selectionBox.style.left = `${left}px`;
  selectionBox.style.top = `${top}px`;
  selectionBox.style.width = `${width}px`;
  selectionBox.style.height = `${height}px`;
}

function finishSelection(event) {
  if (!isSelecting || !selectionStart) return;

  isSelecting = false;
  const end = shellPoint(event);
  updateSelectionBox(selectionStart, end);
  const width = Math.abs(selectionStart.x - end.x);
  const height = Math.abs(selectionStart.y - end.y);
  hasSelection = width > 12 && height > 12;
  lensStatus.textContent = hasSelection
    ? "Selection ready. Scan it for feedback."
    : "Selection was too small. Drag a larger area or scan the full page.";
}

function hideSelection() {
  hasSelection = false;
  selectionStart = null;
  selectionBox.classList.add("hidden");
  lensStatus.textContent = "Select work on the page, or scan the full note.";
}

function beginStroke(event) {
  if (activeTool === "lens") {
    beginSelection(event);
    return;
  }

  isDrawing = true;
  lastPoint = canvasPoint(event);
  canvas.setPointerCapture(event.pointerId);
}

function drawStroke(event) {
  if (activeTool === "lens" && isSelecting) {
    updateSelectionBox(selectionStart, shellPoint(event));
    return;
  }

  if (!isDrawing || !lastPoint) return;

  const nextPoint = canvasPoint(event);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";
  ctx.lineWidth = Number(penSize.value);
  ctx.strokeStyle = activeTool === "eraser" ? "#ffffff" : "#171a21";

  if (activeTool === "eraser") {
    ctx.lineWidth = Number(penSize.value) * 4;
  }

  ctx.beginPath();
  ctx.moveTo(lastPoint.x, lastPoint.y);
  ctx.lineTo(nextPoint.x, nextPoint.y);
  ctx.stroke();

  lastPoint = nextPoint;
}

function endStroke(event) {
  if (activeTool === "lens") {
    finishSelection(event);
    return;
  }

  isDrawing = false;
  lastPoint = null;
  if (canvas.hasPointerCapture(event.pointerId)) {
    canvas.releasePointerCapture(event.pointerId);
  }
}

function setActiveButton(buttons, selectedButton) {
  buttons.forEach((button) => button.classList.toggle("active", button === selectedButton));
}

function setActiveTool(tool) {
  activeTool = tool;
  const selectedButton = [...toolButtons].find((button) => button.dataset.tool === tool);
  if (selectedButton) setActiveButton(toolButtons, selectedButton);

  canvasShell.classList.toggle("lens-active", tool === "lens");
  if (tool === "lens") {
    aiPanel.classList.remove("closed");
    lensStatus.textContent = "Drag around homework, a paragraph, or a diagram to inspect it.";
  }
}

function renderMockFeedback(scope) {
  const prompt = questionInput.value.trim();
  const folder = currentFolder();
  const note = currentNote();
  const scopeCopy = scope === "selection" ? "selected work" : "full page";
  const modeCopy = {
    check: {
      title: "Step check",
      body: "Your setup looks reasonable. <strong>Watch the transition between the second and third lines</strong>; that is where sign errors usually sneak in.",
    },
    hint: {
      title: "Hint",
      body: "Focus on the rule being applied in the selected area. Write the rule once, then compare each term against it before simplifying.",
    },
    grade: {
      title: "Practice grade",
      body: "Estimated score: 7/10. The reasoning is mostly there, but the final simplification needs one more check.",
    },
  };

  const selected = modeCopy[activeMode];
  feedback.innerHTML = `
    <h3>${selected.title}</h3>
    <p>${selected.body}</p>
    <p class="prompt-note">Scanned: ${scopeCopy}. Class: ${escapeHtml(folder.name)}. Note: ${escapeHtml(note.title)}. Context: ${escapeHtml(prompt || "No extra context added.")}</p>
  `;
}

folderForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const name = folderName.value.trim();
  if (!name) return;

  const folder = { id: makeId(), name, notes: [] };
  folders.unshift(folder);
  folderName.value = "";
  renderFolders();
  openFolder(folder.id);
});

folderGrid.addEventListener("click", (event) => {
  const newNoteButton = event.target.closest("[data-new-note]");
  const openFolderButton = event.target.closest("[data-open-folder]");

  if (newNoteButton) {
    createNote(newNoteButton.dataset.newNote);
  }

  if (openFolderButton) {
    openFolder(openFolderButton.dataset.openFolder);
  }
});

notesGrid.addEventListener("click", (event) => {
  const openNoteButton = event.target.closest("[data-open-note]");
  if (openNoteButton) openNote(openNoteButton.dataset.openNote);
});

classBackHome.addEventListener("click", () => {
  renderFolders();
  showView("home");
});

newNoteFromClass.addEventListener("click", () => createNote(currentFolderId));
backClass.addEventListener("click", goToClass);

noteTitle.addEventListener("input", () => {
  const note = currentNote();
  if (note) note.title = noteTitle.value.trim() || "Untitled note";
});

toolButtons.forEach((button) => {
  button.addEventListener("click", () => setActiveTool(button.dataset.tool));
});

modeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    activeMode = button.dataset.mode;
    setActiveButton(modeButtons, button);
  });
});

canvas.addEventListener("pointerdown", beginStroke);
canvas.addEventListener("pointermove", drawStroke);
canvas.addEventListener("pointerup", endStroke);
canvas.addEventListener("pointercancel", endStroke);
canvas.addEventListener("pointerleave", endStroke);

clearCanvas.addEventListener("click", resetCanvas);

scanSelection.addEventListener("click", () => {
  if (!hasSelection) {
    lensStatus.textContent = "Select an area first, or use Scan page.";
    return;
  }
  renderMockFeedback("selection");
});

scanPage.addEventListener("click", () => {
  hideSelection();
  renderMockFeedback("page");
});

renderFolders();
renderNotes();
