const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");
const crypto = require("node:crypto");

loadEnvFile();

const PORT = Number(process.env.PORT) || 8080;
const HOST = process.env.HOST || "0.0.0.0";
const MODEL = process.env.OPENAI_MODEL || "gpt-5-mini";
const PUBLIC_DIR = __dirname;
const SERVICE_NAME = "BetterNotes API";
const REQUEST_BODY_LIMIT_BYTES = Number(process.env.REQUEST_BODY_LIMIT_BYTES) || 60_000_000;
const USAGE_LOG_PREFIX = "[BetterNotesUsage]";
const DATABASE_URL = process.env.DATABASE_URL;

let databasePool;
let databaseReady = false;

const mimeTypes = {
  ".css": "text/css",
  ".html": "text/html",
  ".ico": "image/x-icon",
  ".js": "text/javascript",
  ".json": "application/json",
  ".png": "image/png",
  ".svg": "image/svg+xml",
};

const server = http.createServer(async (request, response) => {
  try {
    const url = new URL(request.url, `http://${request.headers.host}`);

    if (request.method === "GET" && url.pathname === "/api/health") {
      sendJson(response, 200, {
        service: SERVICE_NAME,
        status: "ok",
        aiConfigured: Boolean(process.env.OPENAI_API_KEY),
        databaseConfigured: Boolean(DATABASE_URL),
        databaseReady,
        model: MODEL,
        uptimeSeconds: Math.round(process.uptime()),
      });
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/ready") {
      const aiConfigured = Boolean(process.env.OPENAI_API_KEY);
      sendJson(response, aiConfigured ? 200 : 503, {
        service: SERVICE_NAME,
        status: aiConfigured ? "ready" : "not_ready",
        aiConfigured,
        databaseConfigured: Boolean(DATABASE_URL),
        databaseReady,
        model: MODEL,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/ai-transcribe") {
      await handleAiTranscribe(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/ai-feedback") {
      await handleAiFeedback(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/ai-followup") {
      await handleAiFollowup(request, response);
      return;
    }

    if (request.method !== "GET") {
      sendJson(response, 405, { error: "Method not allowed" });
      return;
    }

    serveStaticFile(url.pathname, response);
  } catch (error) {
    console.error(error);
    const statusCode = error.message === "Request body is too large." ? 413 : 500;
    sendJson(response, statusCode, { error: error.message || "Something went wrong." });
  }
});

server.on("error", (error) => {
  if (error.code === "EADDRINUSE") {
    console.error(`Port ${PORT} is already in use. Stop the other server or set a different PORT.`);
    process.exit(1);
  }

  if (error.code === "EACCES" || error.code === "EPERM") {
    console.error(`BetterNotes API could not listen on ${HOST}:${PORT}. Check permissions or choose another HOST/PORT.`);
    process.exit(1);
  }

  throw error;
});

server.listen(PORT, HOST, () => {
  console.log(`BetterNotes running at http://${HOST}:${PORT}`);
  console.log(`On this Mac, open http://localhost:${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/api/health`);
  if (!process.env.OPENAI_API_KEY) {
    console.warn("OPENAI_API_KEY is not set. AI routes will return setup errors.");
  }
  initializeDatabase().catch((error) => {
    databaseReady = false;
    console.warn("Usage database is not ready. Falling back to Render logs only.", error.message);
  });
});

process.on("SIGTERM", closeServer);
process.on("SIGINT", closeServer);

function closeServer() {
  console.log("Shutting down BetterNotes API...");
  server.close(() => {
    process.exit(0);
  });
}

function loadEnvFile() {
  const envPath = path.join(__dirname, ".env");
  if (!fs.existsSync(envPath)) return;

  const lines = fs.readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const equalsIndex = trimmed.indexOf("=");
    if (equalsIndex === -1) continue;

    const key = trimmed.slice(0, equalsIndex).trim();
    const value = trimmed.slice(equalsIndex + 1).trim().replace(/^["']|["']$/g, "");
    if (!process.env[key]) process.env[key] = value;
  }
}

function serveStaticFile(pathname, response) {
  const requestedPath = pathname === "/" ? "/index.html" : pathname;
  const filePath = path.normalize(path.join(PUBLIC_DIR, requestedPath));
  const relativePath = path.relative(PUBLIC_DIR, filePath);

  if (
    relativePath.startsWith("..") ||
    path.isAbsolute(relativePath) ||
    relativePath.split(path.sep).some((part) => part.startsWith(".")) ||
    path.basename(filePath) === "server.js"
  ) {
    sendJson(response, 403, { error: "Forbidden" });
    return;
  }

  fs.readFile(filePath, (error, content) => {
    if (error) {
      sendJson(response, 404, { error: "Not found" });
      return;
    }

    const extension = path.extname(filePath);
    response.writeHead(200, { "Content-Type": mimeTypes[extension] || "application/octet-stream" });
    response.end(content);
  });
}

async function handleAiTranscribe(request, response) {
  const startedAt = Date.now();
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    logAIUsage(request, {
      route: "ai-transcribe",
      status: 501,
      success: false,
      startedAt,
      errorType: "missing_api_key",
    });
    sendJson(response, 501, {
      error: "OPENAI_API_KEY is not set. Add it to a .env file to enable real AI Lens feedback.",
    });
    return;
  }

  const body = await readJsonBody(request);
  const { image, scope } = body;

  if (!image || !image.startsWith("data:image/")) {
    logAIUsage(request, {
      route: "ai-transcribe",
      status: 400,
      success: false,
      startedAt,
      scope,
      errorType: "invalid_image",
    });
    sendJson(response, 400, { error: "A PNG or JPEG data URL is required." });
    return;
  }

  const responseFromOpenAi = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      text: {
        format: transcriptionSchema(),
      },
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: [
                "You are BetterNotes, an AI tutor inside a student note-taking app.",
                "Only transcribe the handwritten schoolwork in the image.",
                "If any part is unclear, say so directly in the transcription.",
                "Do not solve, grade, correct, or give feedback yet.",
                "Use LaTeX for math expressions, wrapped in inline delimiters like \\(x^2\\) or display delimiters like \\[x^2 + 1\\]. Do not double-escape the backslashes.",
                `Scan scope: ${scope || "selection"}.`,
              ].join("\n"),
            },
            {
              type: "input_image",
              image_url: image,
              detail: "high",
            },
          ],
        },
      ],
    }),
  });

  const data = await responseFromOpenAi.json();

  if (!responseFromOpenAi.ok) {
    console.error(data);
    logAIUsage(request, {
      route: "ai-transcribe",
      status: responseFromOpenAi.status,
      success: false,
      startedAt,
      scope,
      openaiStatus: responseFromOpenAi.status,
      usage: extractUsage(data),
      errorType: "openai_error",
    });
    sendJson(response, responseFromOpenAi.status, {
      error: data.error?.message || "OpenAI could not generate feedback.",
    });
    return;
  }

  const rawText = extractOutputText(data);
  const transcription = parseTranscription(rawText);
  logAIUsage(request, {
    route: "ai-transcribe",
    status: 200,
    success: true,
    startedAt,
    scope,
    usage: extractUsage(data),
  });
  sendJson(response, 200, transcription);
}

async function handleAiFeedback(request, response) {
  const startedAt = Date.now();
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    logAIUsage(request, {
      route: "ai-feedback",
      status: 501,
      success: false,
      startedAt,
      errorType: "missing_api_key",
    });
    sendJson(response, 501, {
      error: "OPENAI_API_KEY is not set. Add it to a .env file to enable real AI Lens feedback.",
    });
    return;
  }

  const body = await readJsonBody(request);
  const {
    transcription,
    mode,
    prompt,
    noteType,
    noteContextText,
    noteContextImages = [],
    noteContextFiles = [],
    referenceText,
    referenceImages = [],
    referenceFiles = [],
  } = body;

  if (!transcription || !transcription.trim()) {
    logAIUsage(request, {
      route: "ai-feedback",
      status: 400,
      success: false,
      startedAt,
      mode,
      noteType,
      errorType: "missing_transcription",
      context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles }),
    });
    sendJson(response, 400, { error: "Approved reading is required." });
    return;
  }

  const modeInstructions = getModeInstructions();
  const content = [
    {
      type: "input_text",
      text: [
        "You are BetterNotes, an AI tutor inside a student note-taking app.",
        "The student approved this reading of their work. Use it as the source of truth.",
        "Use LaTeX for math expressions, wrapped in inline delimiters like \\(x^2\\) or display delimiters like \\[x^2 + 1\\]. Do not double-escape the backslashes.",
        modeInstructions[mode] || modeInstructions.check,
        mode === "grade" && (referenceText || referenceImages.length > 0 || referenceFiles.length > 0)
          ? "When grading, compare the student's work against the attached rubric, answer key, or solutions reference. If the reference conflicts with the student's work, explain the mismatch."
          : "",
        noteType && noteType !== "blank"
          ? "Use the attached assignment context to understand the original question or instructions before responding."
          : "",
        noteContextFiles.length > 0 || referenceFiles.length > 0
          ? "First identify which problem or prompt in the attached assignment best matches the student's scanned work. If the match is uncertain, say what you inferred."
          : "",
        referenceFiles.length > 0 || referenceImages.length > 0
          ? "Use attached rubrics, answer keys, or references only as grading or checking context, not as student work."
          : "",
        `Approved student work: ${transcription.trim()}`,
        noteContextText ? `Assignment context:\n${noteContextText}` : "",
        referenceText ? `Reference text:\n${referenceText}` : "",
        `Student request: ${prompt || "Check my work."}`,
      ]
        .filter(Boolean)
        .join("\n"),
    },
  ];

  appendInputFiles(content, noteContextFiles.slice(0, 2), "assignment context");

  for (const imageUrl of noteContextImages.slice(0, 4)) {
    if (typeof imageUrl === "string" && imageUrl.startsWith("data:image/")) {
      content.push({
        type: "input_image",
        image_url: imageUrl,
        detail: "high",
      });
    }
  }

  appendInputFiles(content, referenceFiles.slice(0, 2), "reference or rubric");

  for (const imageUrl of referenceImages.slice(0, 4)) {
    if (typeof imageUrl === "string" && imageUrl.startsWith("data:image/")) {
      content.push({
        type: "input_image",
        image_url: imageUrl,
        detail: "high",
      });
    }
  }

  const responseFromOpenAi = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      text: {
        format: feedbackSchema(),
      },
      input: [
        {
          role: "user",
          content,
        },
      ],
    }),
  });

  const data = await responseFromOpenAi.json();

  if (!responseFromOpenAi.ok) {
    console.error(data);
    logAIUsage(request, {
      route: "ai-feedback",
      status: responseFromOpenAi.status,
      success: false,
      startedAt,
      mode,
      noteType,
      openaiStatus: responseFromOpenAi.status,
      usage: extractUsage(data),
      errorType: "openai_error",
      context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles }),
    });
    sendJson(response, responseFromOpenAi.status, {
      error: data.error?.message || "OpenAI could not generate feedback.",
    });
    return;
  }

  const rawText = extractOutputText(data);
  const feedback = parseFeedback(rawText);
  logAIUsage(request, {
    route: "ai-feedback",
    status: 200,
    success: true,
    startedAt,
    mode,
    noteType,
    usage: extractUsage(data),
    context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles }),
  });
  sendJson(response, 200, feedback);
}

async function handleAiFollowup(request, response) {
  const startedAt = Date.now();
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    logAIUsage(request, {
      route: "ai-followup",
      status: 501,
      success: false,
      startedAt,
      errorType: "missing_api_key",
    });
    sendJson(response, 501, {
      error: "OPENAI_API_KEY is not set. Add it to a .env file to enable real AI Lens feedback.",
    });
    return;
  }

  const body = await readJsonBody(request);
  const {
    question,
    mode,
    transcription,
    latestFeedback,
    chatMessages = [],
    noteType,
    noteContextText,
    noteContextImages = [],
    noteContextFiles = [],
    referenceText,
    referenceImages = [],
    referenceFiles = [],
    notePageImage,
  } = body;

  if (!question || !question.trim()) {
    logAIUsage(request, {
      route: "ai-followup",
      status: 400,
      success: false,
      startedAt,
      mode,
      noteType,
      errorType: "missing_question",
      context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles, notePageImage, chatMessages }),
    });
    sendJson(response, 400, { error: "A follow-up question is required." });
    return;
  }

  const conversation = chatMessages
    .slice(-8)
    .map((message) => {
      const role = message.role === "user" || message.role === "student" ? "Student" : "BetterNotes";
      return `${role}: ${message.text}`;
    })
    .join("\n");

  const content = [
    {
      type: "input_text",
      text: [
        "You are BetterNotes, an AI tutor in a student note-taking app.",
        "Answer the student's follow-up using the approved reading, current note page, assignment context, and prior feedback as context.",
        "If the student asks whether a specific problem is correct, inspect the current note page and match it against the assignment context when available.",
        "If there is no approved reading yet, rely on the current note page image and assignment context instead of asking the student to paste their work.",
        "Be concise, practical, and student-friendly. Use LaTeX for math with inline delimiters like \\(x^2\\).",
        getModeInstructions()[mode] || getModeInstructions().check,
        noteType && noteType !== "blank"
          ? "Use the attached assignment context to understand the original question or instructions."
          : "",
        noteContextFiles.length > 0 || referenceFiles.length > 0
          ? "First identify which problem or prompt in the attached assignment best matches the student's scanned work or follow-up. If the match is uncertain, say what you inferred."
          : "",
        referenceFiles.length > 0 || referenceImages.length > 0
          ? "Use attached rubrics, answer keys, or references as grading/checking context, not as student work."
          : "",
        `Approved reading: ${transcription || "No approved reading available."}`,
        noteContextText ? `Assignment context:\n${noteContextText}` : "",
        referenceText ? `Reference text:\n${referenceText}` : "",
        latestFeedback
          ? `Latest feedback:\nTitle: ${latestFeedback.title || ""}\nBody: ${latestFeedback.body || ""}\nNext step: ${latestFeedback.nextStep || ""}`
          : "",
        conversation ? `Conversation so far:\n${conversation}` : "",
        `Student follow-up: ${question.trim()}`,
      ]
        .filter(Boolean)
        .join("\n"),
    },
  ];

  if (typeof notePageImage === "string" && notePageImage.startsWith("data:image/")) {
    content.push({
      type: "input_image",
      image_url: notePageImage,
      detail: "high",
    });
  }

  appendInputFiles(content, noteContextFiles.slice(0, 2), "assignment context");

  for (const imageUrl of noteContextImages.slice(0, 4)) {
    if (typeof imageUrl === "string" && imageUrl.startsWith("data:image/")) {
      content.push({
        type: "input_image",
        image_url: imageUrl,
        detail: "high",
      });
    }
  }

  appendInputFiles(content, referenceFiles.slice(0, 2), "reference or rubric");

  for (const imageUrl of referenceImages.slice(0, 4)) {
    if (typeof imageUrl === "string" && imageUrl.startsWith("data:image/")) {
      content.push({
        type: "input_image",
        image_url: imageUrl,
        detail: "high",
      });
    }
  }

  const responseFromOpenAi = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      input: [
        {
          role: "user",
          content,
        },
      ],
    }),
  });

  const data = await responseFromOpenAi.json();

  if (!responseFromOpenAi.ok) {
    console.error(data);
    logAIUsage(request, {
      route: "ai-followup",
      status: responseFromOpenAi.status,
      success: false,
      startedAt,
      mode,
      noteType,
      openaiStatus: responseFromOpenAi.status,
      usage: extractUsage(data),
      errorType: "openai_error",
      context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles, notePageImage, chatMessages }),
    });
    sendJson(response, responseFromOpenAi.status, {
      error: data.error?.message || "OpenAI could not answer the follow-up.",
    });
    return;
  }

  logAIUsage(request, {
    route: "ai-followup",
    status: 200,
    success: true,
    startedAt,
    mode,
    noteType,
    usage: extractUsage(data),
    context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles, notePageImage, chatMessages }),
  });
  sendJson(response, 200, {
    reply: extractOutputText(data) || "I could not answer that follow-up clearly.",
  });
}

function getModeInstructions() {
  return {
    check: "Check the student's work. Point out the most likely mistake or confirm what looks right. Be concise and encouraging.",
    hint: "Give a hint that helps the student make the next move without giving the full answer away.",
    grade: "Estimate a practice grade and explain the main reason for that score. Be fair, brief, and student-friendly.",
  };
}

function appendInputFiles(content, files, label) {
  for (const file of files) {
    const filename = safeFilename(file?.filename || `${label}.pdf`);
    const fileData = file?.fileData || file?.file_data;
    if (typeof fileData === "string" && fileData.startsWith("data:application/pdf;base64,")) {
      content.push({
        type: "input_file",
        filename,
        file_data: fileData,
      });
    }
  }
}

function safeFilename(filename) {
  return String(filename)
    .replace(/[^\w .()-]/g, "_")
    .slice(0, 120) || "attachment.pdf";
}

function logAIUsage(request, event) {
  const payload = {
    event: "ai_usage",
    requestId: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    clientId: clientIdFromRequest(request),
    route: event.route,
    status: event.status,
    success: Boolean(event.success),
    durationMs: Math.max(0, Date.now() - event.startedAt),
    model: MODEL,
    mode: event.mode || null,
    scope: event.scope || null,
    noteType: event.noteType || null,
    openaiStatus: event.openaiStatus || null,
    errorType: event.errorType || null,
    usage: event.usage || emptyUsage(),
    context: event.context || {},
  };

  console.log(`${USAGE_LOG_PREFIX} ${JSON.stringify(payload)}`);
  writeUsageEvent(payload).catch((error) => {
    console.warn("Could not write usage event to database.", error.message);
  });
}

async function initializeDatabase() {
  const pool = getDatabasePool();
  if (!pool) {
    console.log("DATABASE_URL is not set. Usage events will only be written to logs.");
    return;
  }

  await pool.query(`
    create extension if not exists pgcrypto;

    create table if not exists better_notes_users (
      id uuid primary key default gen_random_uuid(),
      install_id text unique not null,
      display_name text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create table if not exists ai_usage_events (
      id uuid primary key default gen_random_uuid(),
      user_id uuid references better_notes_users(id) on delete set null,
      install_id text not null,
      route text not null,
      status integer not null,
      success boolean not null,
      duration_ms integer not null,
      model text not null,
      mode text,
      scope text,
      note_type text,
      openai_status integer,
      error_type text,
      input_tokens integer,
      output_tokens integer,
      total_tokens integer,
      cached_input_tokens integer,
      context jsonb not null default '{}'::jsonb,
      created_at timestamptz not null default now()
    );

    create index if not exists idx_ai_usage_events_created_at
      on ai_usage_events (created_at desc);

    create index if not exists idx_ai_usage_events_install_id_created_at
      on ai_usage_events (install_id, created_at desc);

    create index if not exists idx_ai_usage_events_success
      on ai_usage_events (success);
  `);

  databaseReady = true;
  console.log("Usage database is ready.");
}

function getDatabasePool() {
  if (!DATABASE_URL) return null;
  if (databasePool) return databasePool;

  const { Pool } = require("pg");
  databasePool = new Pool({
    connectionString: DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });

  databasePool.on("error", (error) => {
    databaseReady = false;
    console.warn("Usage database pool error.", error.message);
  });

  return databasePool;
}

async function writeUsageEvent(payload) {
  const pool = getDatabasePool();
  if (!pool) return;

  const userResult = await pool.query(
    `
      insert into better_notes_users (install_id, updated_at)
      values ($1, now())
      on conflict (install_id)
      do update set updated_at = now()
      returning id
    `,
    [payload.clientId]
  );

  const userId = userResult.rows[0]?.id || null;
  const usage = payload.usage || emptyUsage();

  await pool.query(
    `
      insert into ai_usage_events (
        user_id,
        install_id,
        route,
        status,
        success,
        duration_ms,
        model,
        mode,
        scope,
        note_type,
        openai_status,
        error_type,
        input_tokens,
        output_tokens,
        total_tokens,
        cached_input_tokens,
        context,
        created_at
      )
      values (
        $1, $2, $3, $4, $5, $6, $7, $8,
        $9, $10, $11, $12, $13, $14, $15, $16,
        $17::jsonb, $18
      )
    `,
    [
      userId,
      payload.clientId,
      payload.route,
      payload.status,
      payload.success,
      payload.durationMs,
      payload.model,
      payload.mode,
      payload.scope,
      payload.noteType,
      payload.openaiStatus,
      payload.errorType,
      usage.inputTokens,
      usage.outputTokens,
      usage.totalTokens,
      usage.cachedInputTokens,
      JSON.stringify(payload.context || {}),
      payload.timestamp,
    ]
  );
}

function clientIdFromRequest(request) {
  const rawClientId = request.headers["x-betternotes-install-id"];
  if (typeof rawClientId !== "string") return "unknown";

  const cleaned = rawClientId.replace(/[^\w-]/g, "").slice(0, 80);
  return cleaned || "unknown";
}

function extractUsage(data) {
  const usage = data?.usage || {};
  const inputTokens = numberOrNull(usage.input_tokens ?? usage.prompt_tokens);
  const outputTokens = numberOrNull(usage.output_tokens ?? usage.completion_tokens);
  const totalTokens = numberOrNull(usage.total_tokens);
  const cachedInputTokens = numberOrNull(
    usage.input_tokens_details?.cached_tokens ??
      usage.prompt_tokens_details?.cached_tokens
  );

  return {
    inputTokens,
    outputTokens,
    totalTokens: totalTokens ?? sumTokens(inputTokens, outputTokens),
    cachedInputTokens,
  };
}

function emptyUsage() {
  return {
    inputTokens: null,
    outputTokens: null,
    totalTokens: null,
    cachedInputTokens: null,
  };
}

function sumTokens(inputTokens, outputTokens) {
  if (inputTokens === null && outputTokens === null) return null;
  return (inputTokens || 0) + (outputTokens || 0);
}

function numberOrNull(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function contextCounts({
  noteContextImages = [],
  noteContextFiles = [],
  referenceImages = [],
  referenceFiles = [],
  notePageImage,
  chatMessages = [],
}) {
  return {
    assignmentFiles: Array.isArray(noteContextFiles) ? noteContextFiles.length : 0,
    assignmentImages: Array.isArray(noteContextImages) ? noteContextImages.length : 0,
    referenceFiles: Array.isArray(referenceFiles) ? referenceFiles.length : 0,
    referenceImages: Array.isArray(referenceImages) ? referenceImages.length : 0,
    hasNotePageImage: typeof notePageImage === "string" && notePageImage.startsWith("data:image/"),
    chatMessages: Array.isArray(chatMessages) ? chatMessages.length : 0,
  };
}

function feedbackSchema() {
  return {
    type: "json_schema",
    name: "better_notes_feedback",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        title: { type: "string" },
        body: { type: "string" },
        nextStep: { type: "string" },
      },
      required: ["title", "body", "nextStep"],
    },
    strict: true,
  };
}

function transcriptionSchema() {
  return {
    type: "json_schema",
    name: "better_notes_transcription",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        transcription: { type: "string" },
      },
      required: ["transcription"],
    },
    strict: true,
  };
}

function readJsonBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";

    request.on("data", (chunk) => {
      body += chunk;
      if (body.length > REQUEST_BODY_LIMIT_BYTES) {
        reject(new Error("Request body is too large."));
      }
    });

    request.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch (error) {
        reject(error);
      }
    });

    request.on("error", reject);
  });
}

function extractOutputText(data) {
  if (data.output_text) return data.output_text;

  return (data.output || [])
    .flatMap((item) => item.content || [])
    .filter((content) => content.type === "output_text")
    .map((content) => content.text)
    .join("\n");
}

function parseFeedback(rawText) {
  try {
    const trimmedText = rawText.trim();
    const jsonStart = trimmedText.indexOf("{");
    const jsonEnd = trimmedText.lastIndexOf("}");
    const jsonText = jsonStart >= 0 && jsonEnd > jsonStart ? trimmedText.slice(jsonStart, jsonEnd + 1) : trimmedText;
    const parsed = JSON.parse(jsonText);

    return {
      title: String(parsed.title || "AI feedback"),
      body: String(parsed.body || "I could not read enough detail to give specific feedback."),
      nextStep: String(parsed.nextStep || "Try scanning a clearer or smaller section."),
    };
  } catch {
    return {
      title: "AI feedback",
      body: rawText || "I could not read enough detail to give specific feedback.",
      nextStep: "Try scanning a clearer or smaller section.",
    };
  }
}

function parseTranscription(rawText) {
  try {
    const trimmedText = rawText.trim();
    const jsonStart = trimmedText.indexOf("{");
    const jsonEnd = trimmedText.lastIndexOf("}");
    const jsonText = jsonStart >= 0 && jsonEnd > jsonStart ? trimmedText.slice(jsonStart, jsonEnd + 1) : trimmedText;
    const parsed = JSON.parse(jsonText);

    return {
      transcription: String(parsed.transcription || "I could not read enough detail to transcribe this clearly."),
    };
  } catch {
    return {
      transcription: rawText || "I could not read enough detail to transcribe this clearly.",
    };
  }
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
}
