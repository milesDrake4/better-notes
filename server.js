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
const FREE_SCAN_LIMIT = Number(process.env.FREE_SCAN_LIMIT) || 3;
const USAGE_LOG_PREFIX = "[BetterNotesUsage]";
const DATABASE_URL = process.env.DATABASE_URL;
const SUPABASE_URL = normalizeSupabaseURL(process.env.SUPABASE_URL || "");
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "";

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
        authConfigured: isAuthConfigured(),
        authHost: authHostForDiagnostics(),
        databaseConfigured: Boolean(DATABASE_URL),
        databaseReady,
        freeScanLimit: FREE_SCAN_LIMIT,
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
        authConfigured: isAuthConfigured(),
        authHost: authHostForDiagnostics(),
        databaseConfigured: Boolean(DATABASE_URL),
        databaseReady,
        freeScanLimit: FREE_SCAN_LIMIT,
        model: MODEL,
      });
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/waitlist") {
      await handleWaitlistSignup(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/ai-transcribe") {
      await handleAiTranscribe(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/signup") {
      await handleAuthSignup(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/login") {
      await handleAuthLogin(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/refresh") {
      await handleAuthRefresh(request, response);
      return;
    }

    if (request.method === "POST" && url.pathname === "/api/auth/logout") {
      await handleAuthLogout(request, response);
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/auth/me") {
      await handleAuthMe(request, response);
      return;
    }

    if (request.method === "GET" && url.pathname === "/api/account/usage") {
      await handleAccountUsage(request, response);
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
    const statusCode = error.statusCode || (error.message === "Request body is too large." ? 413 : 500);
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
  const requestedPath = pathname === "/" ? "/landing.html" : pathname;
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

  const usageLimit = await checkFreeScanLimit(request);
  if (usageLimit.isLimited) {
    logAIUsage(request, {
      route: "ai-transcribe",
      status: 402,
      success: false,
      startedAt,
      scope: "selection",
      errorType: "free_scan_limit_reached",
      context: {
        freeScanLimit: usageLimit.limit,
        successfulScans: usageLimit.successfulScans,
        remainingScans: usageLimit.remainingScans,
      },
    });
    sendJson(response, 402, {
      error: `You've used your ${usageLimit.limit} free AI scans. Better Notes Pro is coming soon.`,
      code: "free_scan_limit_reached",
      freeScanLimit: usageLimit.limit,
      successfulScans: usageLimit.successfulScans,
      remainingScans: usageLimit.remainingScans,
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

async function handleWaitlistSignup(request, response) {
  const body = await readJsonBody(request);
  const email = normalizeEmail(body.email);
  if (!email) {
    sendJson(response, 400, { error: "Enter a valid email address." });
    return;
  }

  const signup = {
    email,
    name: cleanOptionalText(body.name, 80),
    school: cleanOptionalText(body.school, 120),
    subjects: cleanOptionalText(body.subjects, 180),
    source: cleanOptionalText(body.source, 80) || "landing_page",
    notes: cleanOptionalText(body.notes, 500),
    wantsBeta: body.wantsBeta !== false,
    userAgent: cleanOptionalText(request.headers["user-agent"], 300),
    referrer: cleanOptionalText(request.headers.referer || request.headers.referrer, 300),
  };

  console.log(`[BetterNotesWaitlist] ${JSON.stringify({ ...signup, userAgent: undefined })}`);

  const pool = getDatabasePool();
  if (!pool || !databaseReady) {
    sendJson(response, 202, {
      status: "accepted",
      message: "You're on the Better Notes demo list.",
      databaseReady: false,
    });
    return;
  }

  await pool.query(
    `
      insert into waitlist_signups (
        email,
        name,
        school,
        subjects,
        source,
        notes,
        wants_beta,
        user_agent,
        referrer,
        updated_at
      )
      values ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
      on conflict (email)
      do update set
        name = excluded.name,
        school = excluded.school,
        subjects = excluded.subjects,
        source = excluded.source,
        notes = excluded.notes,
        wants_beta = excluded.wants_beta,
        user_agent = excluded.user_agent,
        referrer = excluded.referrer,
        updated_at = now()
    `,
    [
      signup.email,
      signup.name,
      signup.school,
      signup.subjects,
      signup.source,
      signup.notes,
      signup.wantsBeta,
      signup.userAgent,
      signup.referrer,
    ]
  );

  sendJson(response, 200, {
    status: "ok",
    message: "You're on the Better Notes demo list.",
    databaseReady: true,
  });
}

async function handleAuthSignup(request, response) {
  if (!isAuthConfigured()) {
    sendJson(response, 501, { error: "Supabase Auth is not configured on the BetterNotes server." });
    return;
  }

  const { email, password } = await readJsonBody(request);
  const credentials = validateEmailPassword(email, password);
  if (credentials.error) {
    sendJson(response, 400, { error: credentials.error });
    return;
  }

  const data = await callSupabaseAuth("/auth/v1/signup", {
    method: "POST",
    body: {
      email: credentials.email,
      password: credentials.password,
    },
  });

  sendJson(response, data.access_token ? 200 : 202, authSessionResponse(data));
}

async function handleAuthLogin(request, response) {
  if (!isAuthConfigured()) {
    sendJson(response, 501, { error: "Supabase Auth is not configured on the BetterNotes server." });
    return;
  }

  const { email, password } = await readJsonBody(request);
  const credentials = validateEmailPassword(email, password);
  if (credentials.error) {
    sendJson(response, 400, { error: credentials.error });
    return;
  }

  const data = await callSupabaseAuth("/auth/v1/token?grant_type=password", {
    method: "POST",
    body: {
      email: credentials.email,
      password: credentials.password,
    },
  });

  sendJson(response, 200, authSessionResponse(data));
}

async function handleAuthRefresh(request, response) {
  if (!isAuthConfigured()) {
    sendJson(response, 501, { error: "Supabase Auth is not configured on the BetterNotes server." });
    return;
  }

  const { refreshToken } = await readJsonBody(request);
  if (!refreshToken || typeof refreshToken !== "string") {
    sendJson(response, 400, { error: "A refresh token is required." });
    return;
  }

  const data = await callSupabaseAuth("/auth/v1/token?grant_type=refresh_token", {
    method: "POST",
    body: {
      refresh_token: refreshToken,
    },
  });

  sendJson(response, 200, authSessionResponse(data));
}

async function handleAuthLogout(request, response) {
  if (!isAuthConfigured()) {
    sendJson(response, 501, { error: "Supabase Auth is not configured on the BetterNotes server." });
    return;
  }

  const accessToken = bearerTokenFromRequest(request);
  if (!accessToken) {
    sendJson(response, 200, { ok: true });
    return;
  }

  await callSupabaseAuth("/auth/v1/logout", {
    method: "POST",
    accessToken,
    body: {},
  });

  sendJson(response, 200, { ok: true });
}

async function handleAuthMe(request, response) {
  const authUser = await authenticatedUserFromRequest(request);
  if (!authUser) {
    sendJson(response, 401, { error: "Sign in again to continue." });
    return;
  }

  sendJson(response, 200, {
    user: {
      id: authUser.id,
      email: authUser.email || null,
    },
  });
}

async function handleAccountUsage(request, response) {
  const authUser = await authenticatedUserFromRequest(request);
  const usageSummary = await usageSummaryForRequest(request);

  sendJson(response, 200, {
    email: authUser?.email || null,
    freeScanLimit: usageSummary.limit,
    usedScans: usageSummary.successfulScans,
    remainingScans: usageSummary.remainingScans,
    plan: "Free beta",
    backendStatus: "Connected",
    aiConfigured: Boolean(process.env.OPENAI_API_KEY),
    authConfigured: isAuthConfigured(),
    databaseReady,
  });
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
    chatMessages = [],
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
      context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles, chatMessages }),
    });
    sendJson(response, 400, { error: "Approved reading is required." });
    return;
  }

  const modeInstructions = getModeInstructions();
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
        getSharedFeedbackInstructions(),
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
        conversation
          ? "The student is adding this scan to an existing AI chat. Use the previous conversation as context, but treat the newly approved student work as the main thing to answer."
          : "",
        conversation ? `Conversation so far:\n${conversation}` : "",
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
      context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles, chatMessages }),
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
    context: contextCounts({ noteContextImages, noteContextFiles, referenceImages, referenceFiles, chatMessages }),
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
    check: [
      "You are operating in CHECK WORK mode.",
      "Goal: evaluate the student's current work accurately and efficiently.",
      "Begin the body by clearly classifying the selected work as Correct, Partially correct, Incorrect, or Unclear.",
      "If the work is correct, briefly explain why and stop.",
      "If the work is partially correct, identify what is correct and then state the main remaining issue.",
      "If the work is incorrect, identify the earliest or most important mistake and explain the smallest correction needed.",
      "Distinguish between conceptual errors, algebraic or computational errors, missing justification, notation issues, and incomplete answers when useful.",
      "Do not nitpick harmless stylistic differences.",
      "Do not add unrelated study advice, extra practice, or generic encouragement.",
      "Use nextStep only when there is a clear correction or missing step the student should perform. Set nextStep to null when the work is correct or when the body is complete enough.",
    ].join("\n"),
    hint: [
      "You are operating in HINT mode.",
      "Goal: help the student make progress while preserving productive struggle.",
      "Determine what the student has already done and where they appear to be stuck.",
      "Give the smallest useful hint that can move them forward.",
      "Focus on one idea, correction, or decision at a time.",
      "Do not reveal later steps that the student has not yet reached.",
      "Do not provide the final answer unless the student explicitly requests it.",
      "When useful, ask one guiding question that helps the student notice the next idea.",
      "If the student's current approach is valid, help them continue from it rather than replacing it with a completely different method.",
      "If the selected work is already correct and complete, say so briefly and set nextStep to null.",
      "nextStep is usually appropriate in Hint mode, but never create one merely to fill the field.",
    ].join("\n"),
    grade: [
      "You are operating in GRADE / RUBRIC mode.",
      "Goal: evaluate the student's work against the provided assignment requirements, rubric, answer key, or official solution.",
      "Use an attached rubric whenever one is available.",
      "Follow the rubric's categories, point values, performance levels, and stated requirements as closely as possible.",
      "Identify which parts of the student's work earn credit and which parts lose credit or fail to meet a requirement.",
      "Give a score, point estimate, percentage, letter grade, or performance category only when the available context supports one.",
      "Do not invent exact point values when the rubric does not provide enough information.",
      "Tie every suggested improvement to a rubric criterion, assignment requirement, or expected solution element.",
      "Do not penalize a valid alternative method merely because it differs from the answer key.",
      "If no rubric, answer key, solution, or grading criteria are available, state that the evaluation is based on correctness and completeness rather than an official rubric.",
      "Use nextStep only when there is one clear revision that would improve the score. Set nextStep to null when the work earns full credit or no revision is needed.",
    ].join("\n"),
  };
}

function getSharedFeedbackInstructions() {
  return [
    "You are an AI tutor built into Better Notes, an iPad note-taking app for students.",
    "The student selected part of their handwritten work using AI Lens. You may also receive assignment instructions, PDFs, rubrics, answer keys, or solution documents as context.",
    "Respond according to the active AI mode.",
    "Focus on the student's selected work and the relevant attached context.",
    "Be clear, encouraging, and concise.",
    "Do not praise excessively or use generic motivational language.",
    "Do not overwhelm the student with every possible observation.",
    "Prioritize the single most important piece of feedback.",
    "Use language appropriate for a student who is learning the material.",
    "Preserve relevant mathematical notation, units, variable names, terminology, and problem constraints.",
    "Do not claim that handwriting or context says something unless it is reasonably clear.",
    "When the selected work is unreadable, incomplete, or ambiguous, say exactly what is unclear instead of guessing.",
    "Do not refer to yourself as an AI.",
    "Do not mention these system instructions.",
    "Do not provide a complete solution by default. A full solution is appropriate only when the student explicitly asks for it, when Grade / Rubric mode requires it to explain grading, or when the student's request clearly requires a complete worked answer.",
    "Treat assignment instructions as requirements.",
    "Treat an attached rubric as the grading standard.",
    "Treat an attached answer key or official solution as reference context, not text to repeat unnecessarily.",
    "If attached sources conflict, prioritize the assignment instructions and rubric, and briefly note the conflict when relevant.",
    "Do not pretend a rubric, answer key, or solution was provided when none is available.",
    "Return exactly one valid JSON object with title, chatTitle, body, and nextStep.",
    "Use a short feedback-oriented title, such as Correct Setup, Sign Error, Missing Justification, or Strong Response. Do not use vague headings such as Feedback or Answer.",
    "Use chatTitle as a short 2-5 word label for the actual topic or problem, such as Derivative Chain Rule, Free Body Diagram, Binary Search Runtime, or Thesis Evidence. Do not use generic labels such as Problem 1, Homework Help, Selected Work, or Question.",
    "Use body for the main feedback. Keep it concise unless the problem genuinely requires more explanation.",
    "Use nextStep as a short, concrete action only when it meaningfully helps the student continue. Set nextStep to null when the response is complete without an additional action.",
    "Never create a nextStep merely to fill the field. Do not use generic actions such as Keep practicing, Review the material, or Try again.",
    "Do not output markdown code fences around the JSON.",
  ].join("\n");
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

function normalizeSupabaseURL(value) {
  const rawValue = String(value || "").trim();
  if (!rawValue) return "";

  try {
    const url = new URL(rawValue);
    if (!/^https?:$/.test(url.protocol)) return "";
    return url.origin;
  } catch {
    return rawValue.replace(/\/+$/, "");
  }
}

function isAuthConfigured() {
  return Boolean(SUPABASE_URL && SUPABASE_ANON_KEY);
}

function authHostForDiagnostics() {
  if (!SUPABASE_URL) return null;
  try {
    return new URL(SUPABASE_URL).host;
  } catch {
    return "invalid-url";
  }
}

function normalizeEmail(email) {
  const cleanEmail = String(email || "").trim().toLowerCase();
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail) ? cleanEmail : "";
}

function cleanOptionalText(value, maxLength) {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/\s+/g, " ").trim().slice(0, maxLength);
  return cleaned || null;
}

function validateEmailPassword(email, password) {
  const cleanEmail = normalizeEmail(email);
  const cleanPassword = String(password || "");

  if (!cleanEmail) {
    return { error: "Enter a valid email address." };
  }

  if (cleanPassword.length < 6) {
    return { error: "Password must be at least 6 characters." };
  }

  return { email: cleanEmail, password: cleanPassword };
}

async function callSupabaseAuth(pathname, { method, body, accessToken } = {}) {
  const authURL = supabaseAuthURL(pathname);
  const response = await fetch(authURL, {
    method,
    headers: {
      apikey: SUPABASE_ANON_KEY,
      Authorization: `Bearer ${accessToken || SUPABASE_ANON_KEY}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message =
      data.error_description ||
      data.msg ||
      data.message ||
      data.error ||
      "Supabase Auth returned an error.";
    const error = new Error(message);
    error.statusCode = response.status;
    throw error;
  }

  return data;
}

function supabaseAuthURL(pathname) {
  const baseURL = new URL(SUPABASE_URL);
  return new URL(pathname, baseURL).toString();
}

function authSessionResponse(data) {
  return {
    accessToken: data.access_token || null,
    refreshToken: data.refresh_token || null,
    expiresIn: data.expires_in || null,
    tokenType: data.token_type || "bearer",
    user: data.user
      ? {
          id: data.user.id,
          email: data.user.email || null,
        }
      : null,
    message: data.access_token
      ? null
      : "Check your email to confirm your account, then sign in.",
  };
}

function bearerTokenFromRequest(request) {
  const authorization = request.headers.authorization;
  if (typeof authorization !== "string") return null;

  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : null;
}

async function authenticatedUserFromRequest(request) {
  if (!isAuthConfigured()) return null;
  if (request.betterNotesAuthUser !== undefined) return request.betterNotesAuthUser;
  if (request.betterNotesAuthUserPromise) return request.betterNotesAuthUserPromise;

  request.betterNotesAuthUserPromise = (async () => {
    const accessToken = bearerTokenFromRequest(request);
    if (!accessToken) {
      request.betterNotesAuthUser = null;
      return null;
    }

    try {
      const data = await callSupabaseAuth("/auth/v1/user", {
        method: "GET",
        accessToken,
      });
      const authUser = data?.id
        ? {
            id: data.id,
            email: data.email || null,
          }
        : null;
      request.betterNotesAuthUser = authUser;
      return authUser;
    } catch (error) {
      console.warn("Could not verify BetterNotes auth token.", error.message);
      request.betterNotesAuthUser = null;
      return null;
    }
  })();

  return request.betterNotesAuthUserPromise;
}

function logAIUsage(request, event) {
  const payload = {
    event: "ai_usage",
    requestId: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    clientId: clientIdFromRequest(request),
    authUser: request.betterNotesAuthUser || null,
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
  authenticatedUserFromRequest(request)
    .then((authUser) => writeUsageEvent({ ...payload, authUser }))
    .catch((error) => {
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
      auth_user_id uuid unique,
      email text,
      display_name text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    alter table better_notes_users
      add column if not exists auth_user_id uuid;

    alter table better_notes_users
      add column if not exists email text;

    create unique index if not exists idx_better_notes_users_auth_user_id
      on better_notes_users (auth_user_id);

    create table if not exists waitlist_signups (
      id uuid primary key default gen_random_uuid(),
      email text unique not null,
      name text,
      school text,
      subjects text,
      source text,
      notes text,
      wants_beta boolean not null default true,
      user_agent text,
      referrer text,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    );

    create index if not exists idx_waitlist_signups_created_at
      on waitlist_signups (created_at desc);

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

async function checkFreeScanLimit(request) {
  const summary = await usageSummaryForRequest(request);
  return {
    isLimited: summary.successfulScans >= summary.limit,
    limit: summary.limit,
    successfulScans: summary.successfulScans,
    remainingScans: summary.remainingScans,
  };
}

async function usageSummaryForRequest(request) {
  const limit = Number.isFinite(FREE_SCAN_LIMIT) ? Math.max(0, FREE_SCAN_LIMIT) : 3;
  if (limit === 0) {
    return { limit, successfulScans: 0, remainingScans: 0 };
  }

  const pool = getDatabasePool();
  if (!pool || !databaseReady) {
    return { limit, successfulScans: 0, remainingScans: limit };
  }

  const identity = await identityFromRequest(request);
  if (!identity.authUser && identity.clientId === "unknown") {
    return { limit, successfulScans: 0, remainingScans: limit };
  }

  let result;
  try {
    if (identity.authUser) {
      const userId = await upsertBetterNotesUser(pool, identity);
      result = await pool.query(
        `
          select count(*)::integer as successful_scans
          from ai_usage_events
          where user_id = $1
            and route = 'ai-feedback'
            and success = true
        `,
        [userId]
      );
    } else {
      result = await pool.query(
        `
          select count(*)::integer as successful_scans
          from ai_usage_events
          where install_id = $1
            and route = 'ai-feedback'
            and success = true
        `,
        [identity.clientId]
      );
    }
  } catch (error) {
    console.warn("Could not check free scan limit. Allowing request.", error.message);
    return { limit, successfulScans: 0, remainingScans: limit };
  }

  const successfulScans = Number(result.rows[0]?.successful_scans) || 0;
  const remainingScans = Math.max(0, limit - successfulScans);
  return {
    limit,
    successfulScans,
    remainingScans,
  };
}

async function writeUsageEvent(payload) {
  const pool = getDatabasePool();
  if (!pool) return;

  const userId = await upsertBetterNotesUser(pool, {
    clientId: payload.clientId,
    authUser: payload.authUser || null,
  });
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

async function upsertBetterNotesUser(pool, identity) {
  const clientId = identity.clientId || "unknown";
  const authUser = identity.authUser || null;

  if (authUser?.id) {
    const attachedExistingInstall = await pool.query(
      `
        update better_notes_users
        set auth_user_id = $2,
            email = $3,
            updated_at = now()
        where install_id = $1
          and auth_user_id is null
        returning id
      `,
      [clientId, authUser.id, authUser.email || null]
    );

    if (attachedExistingInstall.rows[0]?.id) {
      return attachedExistingInstall.rows[0].id;
    }

    const userResult = await pool.query(
      `
        insert into better_notes_users (install_id, auth_user_id, email, updated_at)
        values ($1, $2, $3, now())
        on conflict (auth_user_id)
        do update set
          install_id = excluded.install_id,
          email = excluded.email,
          updated_at = now()
        returning id
      `,
      [clientId, authUser.id, authUser.email || null]
    );

    return userResult.rows[0]?.id || null;
  }

  const userResult = await pool.query(
    `
      insert into better_notes_users (install_id, updated_at)
      values ($1, now())
      on conflict (install_id)
      do update set updated_at = now()
      returning id
    `,
    [clientId]
  );

  return userResult.rows[0]?.id || null;
}

function clientIdFromRequest(request) {
  const rawClientId = request.headers["x-betternotes-install-id"];
  if (typeof rawClientId !== "string") return "unknown";

  const cleaned = rawClientId.replace(/[^\w-]/g, "").slice(0, 80);
  return cleaned || "unknown";
}

async function identityFromRequest(request) {
  return {
    clientId: clientIdFromRequest(request),
    authUser: await authenticatedUserFromRequest(request),
  };
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
        chatTitle: { type: "string" },
        body: { type: "string" },
        nextStep: { type: ["string", "null"] },
      },
      required: ["title", "chatTitle", "body", "nextStep"],
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
      chatTitle: String(parsed.chatTitle || parsed.title || "AI chat"),
      body: String(parsed.body || "I could not read enough detail to give specific feedback."),
      nextStep: normalizeOptionalText(parsed.nextStep),
    };
  } catch {
    return {
      title: "AI feedback",
      chatTitle: "AI chat",
      body: rawText || "I could not read enough detail to give specific feedback.",
      nextStep: null,
    };
  }
}

function normalizeOptionalText(value) {
  if (value == null) return null;
  const text = String(value).trim();
  if (!text || text.toLowerCase() === "null" || text.toLowerCase() === "none") return null;
  return text;
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
