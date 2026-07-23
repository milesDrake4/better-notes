const form = document.querySelector("#waitlistForm");
const message = document.querySelector("#formMessage");

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (!message) return;

  const submitButton = form.querySelector("button[type='submit']");
  const formData = new FormData(form);
  const payload = Object.fromEntries(formData.entries());
  payload.wantsBeta = true;

  message.textContent = "Saving your spot...";
  message.classList.remove("error");
  if (submitButton) submitButton.disabled = true;

  try {
    const response = await fetch("/api/waitlist", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(data.error || "Could not save your spot yet.");
    }

    message.textContent = data.message || "You're on the Better Notes demo list.";
    form.reset();
  } catch (error) {
    message.textContent = error.message || "Something went wrong. Try again in a minute.";
    message.classList.add("error");
  } finally {
    if (submitButton) submitButton.disabled = false;
  }
});
