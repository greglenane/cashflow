const statusElement = document.querySelector("#status");
const accountsElement = document.querySelector("#accounts");
const buttons = [...document.querySelectorAll("[data-institution]")];

for (const button of buttons) {
  button.addEventListener("click", () => connect(button.dataset.institution));
}

async function connect(institution) {
  setBusy(true);
  accountsElement.replaceChildren();
  setStatus("Creating a secure Plaid Link session...");

  try {
    const session = await postJson("/api/link-token", { institution });
    const handler = Plaid.create({
      token: session.link_token,
      onSuccess: async (publicToken) => {
        setStatus(`Verifying ${session.institution_name} and storing credentials...`);
        try {
          const result = await postJson("/api/exchange", {
            institution,
            public_token: publicToken,
            session_id: session.session_id,
          });
          renderSuccess(result);
        } catch (error) {
          setStatus(`Failed: ${error.message}`);
        } finally {
          setBusy(false);
        }
      },
      onExit: (error) => {
        setStatus(error ? "Plaid Link exited with an error." : "Linking canceled.");
        setBusy(false);
      },
    });
    handler.open();
  } catch (error) {
    setStatus(`Failed: ${error.message}`);
    setBusy(false);
  }
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data.error ?? "REQUEST_FAILED");
  }
  return data;
}

function renderSuccess(result) {
  setStatus(`${result.institution_name} credentials stored successfully.`);
  for (const account of result.accounts) {
    const item = document.createElement("li");
    const suffix = account.mask ? ` ending ${account.mask}` : "";
    item.textContent = `${account.name ?? account.subtype ?? account.type}${suffix}`;
    accountsElement.append(item);
  }
}

function setBusy(busy) {
  for (const button of buttons) {
    button.disabled = busy;
  }
}

function setStatus(message) {
  statusElement.textContent = message;
}

