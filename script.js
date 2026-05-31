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
const lensHint = document.querySelector("#lensHint");
const selectionBox = document.querySelector("#selectionBox");
const ctx = canvas.getContext("2d");
const penSize = document.querySelector("#penSize");
const clearCanvas = document.querySelector("#clearCanvas");
const noteContextBar = document.querySelector("#noteContextBar");
const noteTypeLabel = document.querySelector("#noteTypeLabel");
const noteContextSummary = document.querySelector("#noteContextSummary");
const noteContextDropzone = document.querySelector("#noteContextDropzone");
const noteContextFile = document.querySelector("#noteContextFile");
const clearNoteContext = document.querySelector("#clearNoteContext");
const toolButtons = document.querySelectorAll("[data-tool]");
const modeButtons = document.querySelectorAll("[data-mode]");
const aiPanel = document.querySelector("#aiPanel");
const aiLensFloat = document.querySelector("#aiLensFloat");
const collapseAiPanel = document.querySelector("#collapseAiPanel");
const lensStatus = document.querySelector("#lensStatus");
const gradeReference = document.querySelector("#gradeReference");
const referenceDropzone = document.querySelector("#referenceDropzone");
const referenceFile = document.querySelector("#referenceFile");
const referenceSummary = document.querySelector("#referenceSummary");
const clearReference = document.querySelector("#clearReference");
const scanSelection = document.querySelector("#scanSelection");
const scanPage = document.querySelector("#scanPage");
const feedback = document.querySelector("#feedback");
const chatCard = document.querySelector("#chatCard");
const chatHistory = document.querySelector("#chatHistory");
const questionLabel = document.querySelector("#questionLabel");
const questionInput = document.querySelector("#questionInput");
const sendFollowup = document.querySelector("#sendFollowup");
const noteSetupModal = document.querySelector("#noteSetupModal");
const noteSetupForm = document.querySelector("#noteSetupForm");
const setupContext = document.querySelector("#setupContext");
const setupContextDropzone = document.querySelector("#setupContextDropzone");
const setupContextFile = document.querySelector("#setupContextFile");
const setupContextSummary = document.querySelector("#setupContextSummary");
const cancelNoteSetup = document.querySelector("#cancelNoteSetup");
const STORAGE_KEY = "betterNotes.folders";
const SKIP_READING_CONFIRM_KEY = "betterNotes.skipReadingConfirm";
const MAX_PDF_CONTEXT_PAGES = 4;

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

function normalizeMathText(value) {
  return value
    .replaceAll("\\\\(", "\\(")
    .replaceAll("\\\\)", "\\)")
    .replaceAll("\\\\[", "\\[")
    .replaceAll("\\\\]", "\\]");
}

function fallbackMathHtml(value) {
  return escapeHtml(value)
    .replace(/\\frac\{([^{}]+)\}\{([^{}]+)\}/g, "<span class=\"math-fraction\"><span>$1</span><span>$2</span></span>")
    .replace(/\^(\{([^{}]+)\}|([A-Za-z0-9+\-=]+))/g, "<sup>$2$3</sup>");
}

function renderMathSegment(value, displayMode = false) {
  const normalizedValue = normalizeMathText(value);
  if (window.katex) {
    return window.katex.renderToString(normalizedValue, {
      displayMode,
      throwOnError: false,
    });
  }

  return `<span class="math-fallback">${fallbackMathHtml(normalizedValue)}</span>`;
}

function formatFeedbackText(value) {
  const normalizedValue = normalizeMathText(value);
  const mathPattern = /(\\\(([\s\S]*?)\\\)|\\\[([\s\S]*?)\\\])/g;
  let lastIndex = 0;
  let html = "";
  let match;

  while ((match = mathPattern.exec(normalizedValue)) !== null) {
    html += escapeHtml(normalizedValue.slice(lastIndex, match.index));
    html += renderMathSegment(match[2] ?? match[3], Boolean(match[3]));
    lastIndex = mathPattern.lastIndex;
  }

  html += escapeHtml(normalizedValue.slice(lastIndex));
  return html.replaceAll("\n", "<br>");
}

function renderFeedbackMath(element = feedback) {
  if (!window.renderMathInElement) return;

  window.renderMathInElement(element, {
    delimiters: [
      { left: "$$", right: "$$", display: true },
      { left: "\\[", right: "\\]", display: true },
      { left: "\\(", right: "\\)", display: false },
    ],
    throwOnError: false,
  });
}

const starterFolders = [
  {
    id: makeId(),
    name: "Calculus",
    notes: [
      { id: makeId(), title: "Implicit differentiation", date: "Today", image: null, type: "homework", contextFiles: [] },
      { id: makeId(), title: "Practice test review", date: "Yesterday", image: null, type: "practiceExam", contextFiles: [] },
    ],
  },
  {
    id: makeId(),
    name: "Chemistry",
    notes: [{ id: makeId(), title: "Stoichiometry worksheet", date: "Mon", image: null, type: "homework", contextFiles: [] }],
  },
  {
    id: makeId(),
    name: "English",
    notes: [{ id: makeId(), title: "Essay evidence map", date: "Fri", image: null, type: "blank", contextFiles: [] }],
  },
];

function loadFolders() {
  try {
    const savedFolders = localStorage.getItem(STORAGE_KEY);
    if (!savedFolders) return starterFolders;

    const parsedFolders = JSON.parse(savedFolders);
    if (!Array.isArray(parsedFolders)) return starterFolders;

    return parsedFolders.map((folder) => ({
      ...folder,
      notes: (folder.notes || []).map((note) => ({
        type: "blank",
        contextFiles: [],
        ...note,
      })),
    }));
  } catch {
    return starterFolders;
  }
}

function saveFolders() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(folders));
  } catch {
    console.warn("BetterNotes could not save to local storage.");
  }
}

let folders = loadFolders();
let isDrawing = false;
let isSelecting = false;
let activeTool = "pen";
let activeMode = "check";
let lastPoint = null;
let selectionStart = null;
let selectionEnd = null;
let hasSelection = false;
let currentFolderId = folders[0]?.id ?? null;
let currentNoteId = null;
let pendingReadingScope = null;
let gradeReferenceFiles = [];
let approvedReading = "";
let latestFeedback = null;
let chatMessages = [];
let pendingNoteFolderId = null;
let setupContextFiles = [];

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
  if (folders.length === 0) {
    folderGrid.innerHTML = `
      <section class="empty-state">
        <div class="empty-icon">BN</div>
        <h3>No class folders yet</h3>
        <p>Create your first class folder, then keep notes, homework, and AI feedback organized by subject.</p>
        <div class="empty-actions">
          <button class="strong-action" type="button" data-focus-folder-form>Start a class folder</button>
        </div>
        <ul class="empty-list" aria-label="Folder examples">
          <li>Calculus homework</li>
          <li>Chemistry labs</li>
          <li>English essays</li>
        </ul>
      </section>
    `;
    return;
  }

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
            <button type="button" data-rename-folder="${folder.id}">Rename</button>
            <button class="danger-action" type="button" data-delete-folder="${folder.id}">Delete</button>
          </div>
        </article>
      `;
    })
    .join("");
}

function renderNotes() {
  const folder = currentFolder();
  if (!folder) return;

  classTitle.textContent = folder.name;

  if (folder.notes.length === 0) {
    notesGrid.innerHTML = `
      <section class="empty-state">
        <div class="empty-icon">01</div>
        <h3>No notes yet</h3>
        <p>Create a blank page for the next assignment, lecture, practice problem, or study session.</p>
        <div class="empty-actions">
          <button class="strong-action" type="button" data-empty-new-note="${folder.id}">Create first note</button>
        </div>
        <ul class="empty-list" aria-label="Note examples">
          <li>Work through a problem set</li>
          <li>Mark up lecture notes</li>
          <li>Use AI Lens when you want feedback</li>
        </ul>
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
            <button type="button" data-rename-note="${note.id}">Rename</button>
            <button class="danger-action" type="button" data-delete-note="${note.id}">Delete</button>
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
  saveFolders();
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

function renameFolder(folderId) {
  const folder = folders.find((item) => item.id === folderId);
  if (!folder) return;

  const nextName = prompt("Rename class folder", folder.name)?.trim();
  if (!nextName || nextName === folder.name) return;

  folder.name = nextName;
  saveFolders();
  renderFolders();
}

function deleteFolder(folderId) {
  const folderIndex = folders.findIndex((folder) => folder.id === folderId);
  if (folderIndex === -1) return;

  const folder = folders[folderIndex];
  const noteWord = folder.notes.length === 1 ? "note" : "notes";
  const shouldDelete = confirm(
    `Delete "${folder.name}" and its ${folder.notes.length} ${noteWord}? This cannot be undone.`,
  );
  if (!shouldDelete) return;

  folders.splice(folderIndex, 1);
  saveFolders();

  if (currentFolderId === folderId) {
    currentFolderId = folders[0]?.id ?? null;
    currentNoteId = null;
  }

  renderFolders();
}

function startNoteSetup(folderId) {
  saveCurrentNoteImage();
  pendingNoteFolderId = folderId;
  setupContextFiles = [];
  setupContextFile.value = "";
  noteSetupForm.reset();
  setupContext.classList.add("hidden");
  updateContextSummary(setupContextSummary, setupContextFiles);
  noteSetupModal.classList.remove("hidden");
}

function closeNoteSetup() {
  pendingNoteFolderId = null;
  setupContextFiles = [];
  noteSetupModal.classList.add("hidden");
}

function createNote(folderId, type = "blank", contextFiles = []) {
  saveCurrentNoteImage();
  currentFolderId = folderId;
  const folder = currentFolder();
  if (!folder) return;

  const note = {
    id: makeId(),
    title: type === "homework" ? "Homework note" : type === "practiceExam" ? "Practice exam note" : "Untitled note",
    date: "Just now",
    image: null,
    type,
    contextFiles,
  };

  folder.notes.unshift(note);
  saveFolders();
  openNote(note.id);
}

function renameNote(noteId) {
  const folder = currentFolder();
  const note = folder?.notes.find((item) => item.id === noteId);
  if (!note) return;

  const nextTitle = prompt("Rename note", note.title)?.trim();
  if (!nextTitle || nextTitle === note.title) return;

  note.title = nextTitle;
  saveFolders();
  renderNotes();
}

function deleteNote(noteId) {
  const folder = currentFolder();
  const noteIndex = folder?.notes.findIndex((note) => note.id === noteId);
  if (noteIndex === undefined || noteIndex === -1) return;

  const note = folder.notes[noteIndex];
  const shouldDelete = confirm(`Delete "${note.title}"? This cannot be undone.`);
  if (!shouldDelete) return;

  folder.notes.splice(noteIndex, 1);
  saveFolders();

  if (currentNoteId === noteId) {
    currentNoteId = null;
  }

  renderNotes();
  renderFolders();
}

function openNote(noteId) {
  currentNoteId = noteId;
  const folder = currentFolder();
  const note = currentNote();

  folderCrumb.textContent = folder.name;
  noteTitle.value = note.title;
  renderNoteContext();
  setActiveTool("pen");
  aiPanel.classList.add("closed");
  aiLensFloat.classList.remove("hidden");
  updateComposerMode(false);
  feedback.innerHTML = `
    <div class="feedback-empty">
      <h3>Ready for feedback</h3>
      <p>Use AI Lens when you want BetterNotes to check a piece of handwritten work.</p>
      <ol>
        <li>Tap AI Lens.</li>
        <li>Drag over the work.</li>
        <li>Scan the selection.</li>
      </ol>
    </div>
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
  lensHint.classList.add("hidden");
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
  selectionEnd = shellPoint(event);
  updateSelectionBox(selectionStart, selectionEnd);
  const width = Math.abs(selectionStart.x - selectionEnd.x);
  const height = Math.abs(selectionStart.y - selectionEnd.y);
  hasSelection = width > 12 && height > 12;
  lensStatus.textContent = hasSelection
    ? "Selection ready. Scan it for feedback."
    : "Selection was too small. Drag a larger area or scan the full page.";
}

function hideSelection() {
  hasSelection = false;
  selectionStart = null;
  selectionEnd = null;
  selectionBox.classList.add("hidden");
  lensHint.classList.toggle("hidden", activeTool !== "lens");
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
  saveCurrentNoteImage();
}

function setActiveButton(buttons, selectedButton) {
  buttons.forEach((button) => button.classList.toggle("active", button === selectedButton));
}

function openAiPanel() {
  aiPanel.classList.remove("closed");
  aiLensFloat.classList.add("hidden");
}

function closeAiPanel() {
  aiPanel.classList.add("closed");
  aiLensFloat.classList.remove("hidden");
}

function setActiveTool(tool) {
  activeTool = tool;
  const selectedButton = [...toolButtons].find((button) => button.dataset.tool === tool);
  if (selectedButton) {
    setActiveButton(toolButtons, selectedButton);
  } else {
    toolButtons.forEach((button) => button.classList.remove("active"));
  }

  canvasShell.classList.toggle("lens-active", tool === "lens");
  lensHint.classList.toggle("hidden", tool !== "lens");
  if (tool === "lens") {
    openAiPanel();
    lensStatus.textContent = "Drag around homework, a paragraph, or a diagram to inspect it.";
  } else {
    hideSelection();
  }
}

function updateGradeReferenceVisibility() {
  gradeReference.classList.toggle("hidden", activeMode !== "grade");
}

function updateReferenceSummary() {
  if (gradeReferenceFiles.length === 0) {
    referenceSummary.textContent = "No reference attached.";
    return;
  }

  referenceSummary.textContent = gradeReferenceFiles
    .map((file) => `${file.name} (${file.kind})`)
    .join(", ");
}

function noteTypeCopy(type) {
  return {
    blank: "Blank note",
    homework: "Homework",
    practiceExam: "Practice exam",
  }[type] || "Blank note";
}

function updateContextSummary(element, files) {
  if (!files || files.length === 0) {
    element.textContent = "No context attached.";
    return;
  }

  element.textContent = files.map((file) => `${file.name} (${file.kind})`).join(", ");
}

function renderUploadProgress(element, label = "Uploading", percent = 0) {
  element.innerHTML = `
    <div class="upload-progress">
      <div class="upload-progress-label">${escapeHtml(label)}</div>
      <div class="upload-progress-track">
        <div class="upload-progress-fill" style="width: ${Math.max(0, Math.min(100, percent))}%"></div>
      </div>
    </div>
  `;
}

function updateUploadProgress(element, label, current, total) {
  const percent = total > 0 ? Math.round((current / total) * 100) : 0;
  renderUploadProgress(element, label, percent);
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => resolve(reader.result));
    reader.addEventListener("error", reject);
    reader.readAsDataURL(file);
  });
}

function readFileAsText(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => resolve(reader.result));
    reader.addEventListener("error", reject);
    reader.readAsText(file);
  });
}

function readFileAsArrayBuffer(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.addEventListener("load", () => resolve(reader.result));
    reader.addEventListener("error", reject);
    reader.readAsArrayBuffer(file);
  });
}

function waitForPdfJs() {
  return new Promise((resolve) => {
    if (window.pdfjsLib) {
      resolve(window.pdfjsLib);
      return;
    }

    let attempts = 0;
    const timer = window.setInterval(() => {
      attempts += 1;
      if (window.pdfjsLib || attempts >= 30) {
        window.clearInterval(timer);
        resolve(window.pdfjsLib);
      }
    }, 100);
  });
}

async function pdfToContextImages(file, onPageProgress) {
  const pdfjsLib = await waitForPdfJs();
  if (!pdfjsLib) {
    return [
      {
        kind: "unsupported",
        name: file.name,
        text: "PDF support is still loading. Try again in a moment.",
      },
    ];
  }

  const buffer = await readFileAsArrayBuffer(file);
  const pdf = await pdfjsLib.getDocument({ data: buffer }).promise;
  const pageCount = Math.min(pdf.numPages, MAX_PDF_CONTEXT_PAGES);
  const pages = [];

  for (let pageNumber = 1; pageNumber <= pageCount; pageNumber += 1) {
    const page = await pdf.getPage(pageNumber);
    const viewport = page.getViewport({ scale: 1.6 });
    const pageCanvas = document.createElement("canvas");
    pageCanvas.width = Math.round(viewport.width);
    pageCanvas.height = Math.round(viewport.height);

    await page.render({
      canvasContext: pageCanvas.getContext("2d"),
      viewport,
    }).promise;

    pages.push({
      kind: "image",
      name: `${file.name} page ${pageNumber}`,
      dataUrl: pageCanvas.toDataURL("image/jpeg", 0.86),
    });

    if (onPageProgress) onPageProgress(pageNumber, pageCount);
  }

  return pages;
}

async function addReferenceFiles(files) {
  const nextFiles = [];
  const fileList = [...files];
  renderUploadProgress(referenceSummary, "Preparing upload", 5);

  for (let index = 0; index < fileList.length; index += 1) {
    const file = fileList[index];
    updateUploadProgress(referenceSummary, `Reading ${file.name}`, index, fileList.length);

    if (file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf")) {
      nextFiles.push(
        ...(await pdfToContextImages(file, (pageNumber, pageCount) => {
          const fileProgress = (index + pageNumber / pageCount) / fileList.length;
          renderUploadProgress(referenceSummary, `Converting ${file.name} page ${pageNumber}`, fileProgress * 100);
        })),
      );
      continue;
    }

    if (file.type.startsWith("image/")) {
      nextFiles.push({
        kind: "image",
        name: file.name,
        dataUrl: await readFileAsDataUrl(file),
      });
      continue;
    }

    if (
      file.type.startsWith("text/") ||
      [".txt", ".md", ".csv", ".json"].some((extension) => file.name.toLowerCase().endsWith(extension))
    ) {
      nextFiles.push({
        kind: "text",
        name: file.name,
        text: await readFileAsText(file),
      });
      continue;
    }

    nextFiles.push({
      kind: "unsupported",
      name: file.name,
      text: "Unsupported file type. Use an image or text file for now.",
    });
  }

  gradeReferenceFiles = nextFiles;
  renderUploadProgress(referenceSummary, "Upload ready", 100);
  window.setTimeout(updateReferenceSummary, 250);
}

async function readContextFiles(files, progressElement = null) {
  const contextFiles = [];
  const fileList = [...files];

  if (progressElement) renderUploadProgress(progressElement, "Preparing upload", 5);

  for (let index = 0; index < fileList.length; index += 1) {
    const file = fileList[index];
    if (progressElement) updateUploadProgress(progressElement, `Reading ${file.name}`, index, fileList.length);

    if (file.type === "application/pdf" || file.name.toLowerCase().endsWith(".pdf")) {
      contextFiles.push(
        ...(await pdfToContextImages(file, (pageNumber, pageCount) => {
          if (!progressElement) return;
          const fileProgress = (index + pageNumber / pageCount) / fileList.length;
          renderUploadProgress(progressElement, `Converting ${file.name} page ${pageNumber}`, fileProgress * 100);
        })),
      );
      continue;
    }

    if (file.type.startsWith("image/")) {
      contextFiles.push({
        kind: "image",
        name: file.name,
        dataUrl: await readFileAsDataUrl(file),
      });
      continue;
    }

    if (
      file.type.startsWith("text/") ||
      [".txt", ".md", ".csv", ".json"].some((extension) => file.name.toLowerCase().endsWith(extension))
    ) {
      contextFiles.push({
        kind: "text",
        name: file.name,
        text: await readFileAsText(file),
      });
    }
  }

  if (progressElement) renderUploadProgress(progressElement, "Upload ready", 100);
  return contextFiles;
}

async function addSetupContextFiles(files) {
  setupContextFiles = await readContextFiles(files, setupContextSummary);
  window.setTimeout(() => updateContextSummary(setupContextSummary, setupContextFiles), 250);
}

async function addNoteContextFiles(files) {
  const note = currentNote();
  if (!note) return;

  note.contextFiles = await readContextFiles(files, noteContextSummary);
  window.setTimeout(() => {
    saveFolders();
    renderNoteContext();
  }, 250);
}

function bindDropTarget(target, onFiles) {
  target.addEventListener("dragenter", (event) => {
    event.preventDefault();
    event.stopPropagation();
    target.classList.add("drag-over");
  });

  target.addEventListener("dragover", (event) => {
    event.preventDefault();
    event.stopPropagation();
    target.classList.add("drag-over");
  });

  target.addEventListener("dragleave", (event) => {
    event.preventDefault();
    event.stopPropagation();
    if (!target.contains(event.relatedTarget)) {
      target.classList.remove("drag-over");
    }
  });

  target.addEventListener("drop", (event) => {
    event.preventDefault();
    event.stopPropagation();
    target.classList.remove("drag-over");
    const files = event.dataTransfer?.files;
    if (files?.length) onFiles(files);
  });
}

function renderNoteContext() {
  const note = currentNote();
  if (!note) return;

  note.type = note.type || "blank";
  note.contextFiles = note.contextFiles || [];
  noteContextBar.classList.toggle("hidden", note.type === "blank");
  noteTypeLabel.textContent = noteTypeCopy(note.type);
  updateContextSummary(noteContextSummary, note.contextFiles);
}

function selectionToCanvasRect() {
  if (!selectionStart || !selectionEnd) return null;

  const canvasRect = canvas.getBoundingClientRect();
  const shellRect = canvasShell.getBoundingClientRect();
  const canvasLeft = canvasRect.left - shellRect.left;
  const canvasTop = canvasRect.top - shellRect.top;
  const displayScaleX = canvas.width / canvasRect.width;
  const displayScaleY = canvas.height / canvasRect.height;
  const left = Math.min(selectionStart.x, selectionEnd.x) - canvasLeft;
  const top = Math.min(selectionStart.y, selectionEnd.y) - canvasTop;
  const width = Math.abs(selectionStart.x - selectionEnd.x);
  const height = Math.abs(selectionStart.y - selectionEnd.y);

  return {
    x: Math.max(0, Math.round(left * displayScaleX)),
    y: Math.max(0, Math.round(top * displayScaleY)),
    width: Math.min(canvas.width, Math.round(width * displayScaleX)),
    height: Math.min(canvas.height, Math.round(height * displayScaleY)),
  };
}

function imageForScope(scope) {
  if (scope === "page") return canvas.toDataURL("image/png");

  const rect = selectionToCanvasRect();
  if (!rect || rect.width <= 0 || rect.height <= 0) return null;

  const selectionCanvas = document.createElement("canvas");
  selectionCanvas.width = rect.width;
  selectionCanvas.height = rect.height;
  const selectionCtx = selectionCanvas.getContext("2d");
  selectionCtx.drawImage(canvas, rect.x, rect.y, rect.width, rect.height, 0, 0, rect.width, rect.height);
  return selectionCanvas.toDataURL("image/png");
}

function renderLoadingFeedback(scope) {
  const scopeCopy = scope === "selection" ? "selection" : "page";
  const isSkippingConfirm = localStorage.getItem(SKIP_READING_CONFIRM_KEY) === "true";
  feedback.innerHTML = `
    <h3>Reading ${scopeCopy}...</h3>
    <p>BetterNotes is looking over the handwriting${isSkippingConfirm ? " and will check it right away." : "."}</p>
    ${isSkippingConfirm ? '<button class="ghost-button inline-action" type="button" data-enable-reading-confirm>Review reading next time</button>' : ""}
  `;
}

function renderReadingApproval(result, scope) {
  const scopeCopy = {
    selection: "selected work",
    page: "full page",
  }[scope] || "selected work";
  const transcription = normalizeMathText(result.transcription || "");
  feedback.innerHTML = `
    <section class="reading-check">
      <div class="reading-header">
        <label for="aiTranscription">I read this as</label>
        <button class="text-button" type="button" data-toggle-reading-edit>Edit</button>
      </div>
      <div class="transcription-preview">${formatFeedbackText(transcription || "I could not read enough detail to transcribe this clearly.")}</div>
      <textarea id="aiTranscription" class="hidden" rows="3">${escapeHtml(transcription)}</textarea>
      <div class="reading-actions">
        <button class="primary-button" type="button" data-approve-reading>Looks right</button>
        <button class="ghost-button" type="button" data-toggle-reading-edit>Edit reading</button>
      </div>
      <label class="skip-reading">
        <input type="checkbox" data-skip-reading-confirm />
        <span>Skip this confirmation next time</span>
      </label>
    </section>
    <p class="prompt-note">Scanned: ${scopeCopy}.</p>
  `;
  pendingReadingScope = scope;
  renderFeedbackMath();
}

function renderAiFeedback(result, scope, transcription) {
  const scopeCopy = {
    selection: "selected work",
    page: "full page",
    "approved reading": "approved reading",
  }[scope] || "selected work";
  feedback.innerHTML = `
    <section class="feedback-result">
      <h3>${escapeHtml(result.title || "AI feedback")}</h3>
      <p>${formatFeedbackText(result.body || "I could not read enough detail to give specific feedback.")}</p>
      <p class="prompt-note"><strong>Next step:</strong> ${formatFeedbackText(result.nextStep || "Try scanning a clearer or smaller section.")}</p>
    </section>
    ${transcription ? `<p class="prompt-note"><strong>I read this as:</strong> ${formatFeedbackText(transcription)}</p>` : ""}
    <p class="prompt-note">Scanned: ${scopeCopy}.</p>
  `;
  approvedReading = transcription || approvedReading;
  latestFeedback = result;
  updateComposerMode(true);
  chatMessages = [];
  questionInput.value = "";
  renderChatHistory();
  renderFeedbackMath();
}

function renderChatHistory() {
  chatHistory.innerHTML = chatMessages
    .map(
      (message) => `
        <div class="chat-message ${message.role === "user" ? "user-message" : "assistant-message"}">
          <p>${formatFeedbackText(message.text)}</p>
        </div>
      `,
    )
    .join("");
  chatHistory.classList.toggle("hidden", chatMessages.length === 0);
  renderFeedbackMath(chatHistory);
  chatHistory.scrollTop = chatHistory.scrollHeight;
}

function updateComposerMode(hasFeedback) {
  chatHistory.classList.toggle("hidden", !hasFeedback || chatMessages.length === 0);
  sendFollowup.classList.toggle("hidden", !hasFeedback);
  questionLabel.textContent = hasFeedback ? "Ask a follow-up" : "Tell AI what to focus on";
  questionInput.placeholder = hasFeedback
    ? "Ask about the feedback, a step, or what to try next."
    : "Example: check whether my proof is onto, but do not give away the full answer.";
}

function renderAiError(message) {
  const isSetupError = message.includes("OPENAI_API_KEY") || message.includes("Failed to fetch");
  feedback.innerHTML = `
    <h3>${isSetupError ? "AI Lens is not connected yet" : "AI Lens could not scan this"}</h3>
    <p>${escapeHtml(message)}</p>
    <p class="prompt-note">Check the VS Code terminal for the server message, then try scanning again.</p>
  `;
}

async function requestAiFeedback(scope) {
  const image = imageForScope(scope);
  const folder = currentFolder();
  const note = currentNote();

  if (!image || !folder || !note) {
    lensStatus.textContent = "Select an area first, or use Scan page.";
    return;
  }

  approvedReading = "";
  latestFeedback = null;
  chatMessages = [];
  updateComposerMode(false);
  renderChatHistory();
  renderLoadingFeedback(scope);
  lensStatus.textContent = "Reading handwriting...";

  try {
    const response = await fetch("/api/ai-transcribe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        image,
        mode: activeMode,
        prompt: questionInput.value.trim(),
        scope,
      }),
    });

    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "AI Lens could not scan this note.");

    if (localStorage.getItem(SKIP_READING_CONFIRM_KEY) === "true") {
      await requestApprovedFeedback(result.transcription, scope);
      return;
    }

    renderReadingApproval(result, scope);
    lensStatus.textContent = "Approve the reading before feedback.";
  } catch (error) {
    renderAiError(error.message);
    lensStatus.textContent = "AI Lens needs setup before it can scan.";
  }
}

async function requestApprovedFeedback(approvedText, scope = pendingReadingScope || "selection") {
  const folder = currentFolder();
  const note = currentNote();
  const transcription = normalizeMathText(approvedText || "").trim();

  if (!transcription || !folder || !note) return;

  feedback.innerHTML = `
    <h3>Checking your work...</h3>
    <p>BetterNotes is using the approved reading as the source of truth.</p>
  `;
  lensStatus.textContent = "Checking approved reading...";

  try {
    const noteContextText = (note.contextFiles || [])
      .filter((file) => file.kind === "text")
      .map((file) => `${file.name}:\n${file.text}`)
      .join("\n\n");
    const noteContextImages = (note.contextFiles || [])
      .filter((file) => file.kind === "image")
      .map((file) => file.dataUrl);
    const referenceText = activeMode === "grade"
      ? gradeReferenceFiles
          .filter((file) => file.kind === "text")
          .map((file) => `${file.name}:\n${file.text}`)
          .join("\n\n")
      : "";
    const referenceImages = activeMode === "grade"
      ? gradeReferenceFiles.filter((file) => file.kind === "image").map((file) => file.dataUrl)
      : [];

    const response = await fetch("/api/ai-feedback", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        transcription,
        mode: activeMode,
        prompt: questionInput.value.trim(),
        noteType: note.type || "blank",
        noteContextText,
        noteContextImages,
        referenceText,
        referenceImages,
      }),
    });

    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "BetterNotes could not check the approved reading.");

    renderAiFeedback(result, scope, transcription);
    lensStatus.textContent = "Feedback ready.";
  } catch (error) {
    renderAiError(error.message);
    lensStatus.textContent = "Approved reading could not be checked.";
  }
}

function approveReading() {
  const transcription = feedback.querySelector("#aiTranscription");
  const preview = feedback.querySelector(".transcription-preview");
  const approvedText = transcription?.value.trim() || preview?.textContent.trim();
  const skipReadingConfirm = feedback.querySelector("[data-skip-reading-confirm]")?.checked;

  localStorage.setItem(SKIP_READING_CONFIRM_KEY, skipReadingConfirm ? "true" : "false");
  requestApprovedFeedback(approvedText);
}

async function sendFollowupMessage() {
  const question = questionInput.value.trim();
  if (!question) return;

  chatMessages.push({ role: "user", text: question });
  questionInput.value = "";
  renderChatHistory();
  lensStatus.textContent = "Answering follow-up...";
  sendFollowup.disabled = true;

  try {
    const response = await fetch("/api/ai-followup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        question,
        transcription: approvedReading,
        latestFeedback,
        chatMessages,
        noteType: currentNote()?.type || "blank",
        noteContextText: (currentNote()?.contextFiles || [])
          .filter((file) => file.kind === "text")
          .map((file) => `${file.name}:\n${file.text}`)
          .join("\n\n"),
        noteContextImages: (currentNote()?.contextFiles || [])
          .filter((file) => file.kind === "image")
          .map((file) => file.dataUrl),
        notePageImage: canvas.toDataURL("image/png"),
      }),
    });

    const result = await response.json();
    if (!response.ok) throw new Error(result.error || "BetterNotes could not answer the follow-up.");

    chatMessages.push({ role: "assistant", text: result.reply });
    renderChatHistory();
    lensStatus.textContent = "Follow-up answered.";
  } catch (error) {
    chatMessages.push({ role: "assistant", text: error.message });
    renderChatHistory();
    lensStatus.textContent = "Follow-up could not be answered.";
  } finally {
    sendFollowup.disabled = false;
  }
}

function toggleReadingEditor() {
  const transcription = feedback.querySelector("#aiTranscription");
  const preview = feedback.querySelector(".transcription-preview");
  const toggleButton = feedback.querySelector("[data-toggle-reading-edit]");
  if (!transcription || !preview || !toggleButton) return;

  const isEditing = transcription.classList.toggle("hidden");
  preview.classList.toggle("hidden", !isEditing);
  toggleButton.textContent = isEditing ? "Edit" : "Preview";

  if (!isEditing) {
    transcription.focus();
    return;
  }

  preview.innerHTML = formatFeedbackText(transcription.value || "I could not read enough detail to transcribe this clearly.");
  renderFeedbackMath();
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
  renderFeedbackMath();
}

folderForm.addEventListener("submit", (event) => {
  event.preventDefault();
  const name = folderName.value.trim();
  if (!name) return;

  const folder = { id: makeId(), name, notes: [] };
  folders.unshift(folder);
  folderName.value = "";
  saveFolders();
  renderFolders();
  openFolder(folder.id);
});

folderGrid.addEventListener("click", (event) => {
  const focusFolderFormButton = event.target.closest("[data-focus-folder-form]");
  const newNoteButton = event.target.closest("[data-new-note]");
  const openFolderButton = event.target.closest("[data-open-folder]");
  const renameFolderButton = event.target.closest("[data-rename-folder]");
  const deleteFolderButton = event.target.closest("[data-delete-folder]");

  if (focusFolderFormButton) {
    folderName.focus();
    return;
  }

  if (newNoteButton) {
    startNoteSetup(newNoteButton.dataset.newNote);
    return;
  }

  if (openFolderButton) {
    openFolder(openFolderButton.dataset.openFolder);
    return;
  }

  if (renameFolderButton) {
    renameFolder(renameFolderButton.dataset.renameFolder);
    return;
  }

  if (deleteFolderButton) {
    deleteFolder(deleteFolderButton.dataset.deleteFolder);
  }
});

notesGrid.addEventListener("click", (event) => {
  const openNoteButton = event.target.closest("[data-open-note]");
  const emptyNewNoteButton = event.target.closest("[data-empty-new-note]");
  const renameNoteButton = event.target.closest("[data-rename-note]");
  const deleteNoteButton = event.target.closest("[data-delete-note]");

  if (emptyNewNoteButton) {
    startNoteSetup(emptyNewNoteButton.dataset.emptyNewNote);
    return;
  }

  if (openNoteButton) {
    openNote(openNoteButton.dataset.openNote);
    return;
  }

  if (renameNoteButton) {
    renameNote(renameNoteButton.dataset.renameNote);
    return;
  }

  if (deleteNoteButton) {
    deleteNote(deleteNoteButton.dataset.deleteNote);
  }
});

classBackHome.addEventListener("click", () => {
  renderFolders();
  showView("home");
});

newNoteFromClass.addEventListener("click", () => startNoteSetup(currentFolderId));
backClass.addEventListener("click", goToClass);

noteTitle.addEventListener("input", () => {
  const note = currentNote();
  if (note) note.title = noteTitle.value.trim() || "Untitled note";
  saveFolders();
});

toolButtons.forEach((button) => {
  button.addEventListener("click", () => setActiveTool(button.dataset.tool));
});

aiLensFloat.addEventListener("click", () => setActiveTool("lens"));
collapseAiPanel.addEventListener("click", closeAiPanel);

modeButtons.forEach((button) => {
  button.addEventListener("click", () => {
    activeMode = button.dataset.mode;
    setActiveButton(modeButtons, button);
    updateGradeReferenceVisibility();
  });
});

referenceFile.addEventListener("change", () => {
  addReferenceFiles(referenceFile.files);
});

bindDropTarget(referenceDropzone, addReferenceFiles);

clearReference.addEventListener("click", () => {
  gradeReferenceFiles = [];
  referenceFile.value = "";
  updateReferenceSummary();
});

noteSetupForm.addEventListener("change", (event) => {
  if (event.target.name !== "noteType") return;
  setupContext.classList.toggle("hidden", event.target.value === "blank");
});

setupContextFile.addEventListener("change", () => {
  addSetupContextFiles(setupContextFile.files);
});

bindDropTarget(setupContextDropzone, addSetupContextFiles);

noteSetupForm.addEventListener("submit", (event) => {
  event.preventDefault();
  if (!pendingNoteFolderId) return;

  const selectedType = new FormData(noteSetupForm).get("noteType") || "blank";
  createNote(pendingNoteFolderId, selectedType, setupContextFiles);
  closeNoteSetup();
});

cancelNoteSetup.addEventListener("click", closeNoteSetup);

noteContextFile.addEventListener("change", () => {
  addNoteContextFiles(noteContextFile.files);
});

bindDropTarget(noteContextDropzone, addNoteContextFiles);

clearNoteContext.addEventListener("click", () => {
  const note = currentNote();
  if (!note) return;

  note.contextFiles = [];
  noteContextFile.value = "";
  saveFolders();
  renderNoteContext();
});

["dragover", "drop"].forEach((eventName) => {
  window.addEventListener(eventName, (event) => {
    event.preventDefault();
  });
});

sendFollowup.addEventListener("click", sendFollowupMessage);

questionInput.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" || event.shiftKey) return;

  event.preventDefault();
  if (latestFeedback) {
    sendFollowupMessage();
    return;
  }

  if (!hasSelection) {
    lensStatus.textContent = "Select an area first, or use Scan page.";
    return;
  }

  requestAiFeedback("selection");
});

canvas.addEventListener("pointerdown", beginStroke);
canvas.addEventListener("pointermove", drawStroke);
canvas.addEventListener("pointerup", endStroke);
canvas.addEventListener("pointercancel", endStroke);
canvas.addEventListener("pointerleave", endStroke);

clearCanvas.addEventListener("click", () => {
  resetCanvas();
  saveCurrentNoteImage();
});

scanSelection.addEventListener("click", () => {
  if (!hasSelection) {
    lensStatus.textContent = "Select an area first, or use Scan page.";
    return;
  }
  requestAiFeedback("selection");
});

scanPage.addEventListener("click", () => {
  hideSelection();
  requestAiFeedback("page");
});

feedback.addEventListener("click", (event) => {
  const approveButton = event.target.closest("[data-approve-reading]");
  const enableConfirmButton = event.target.closest("[data-enable-reading-confirm]");
  const toggleButton = event.target.closest("[data-toggle-reading-edit]");

  if (enableConfirmButton) {
    localStorage.setItem(SKIP_READING_CONFIRM_KEY, "false");
    lensStatus.textContent = "Reading confirmation will appear next time.";
    return;
  }

  if (toggleButton) {
    toggleReadingEditor();
    return;
  }

  if (approveButton) approveReading();
});

window.addEventListener("beforeunload", saveCurrentNoteImage);

renderFolders();
renderNotes();
updateGradeReferenceVisibility();
