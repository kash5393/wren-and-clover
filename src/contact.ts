const contactForm = document.querySelector<HTMLFormElement>(".contact-form");

function showError(field: HTMLElement, message: string): void {
  const wrapper = field.parentElement;
  if (!wrapper) {
    return;
  }
  let error = wrapper.querySelector<HTMLSpanElement>(".field-error");
  if (!error) {
    error = document.createElement("span");
    error.className = "field-error";
    wrapper.append(error);
  }
  error.textContent = message;
  field.setAttribute("aria-invalid", message ? "true" : "false");
}

if (contactForm) {
  contactForm.noValidate = true;

  const formStatus = document.createElement("p");
  formStatus.className = "form-status";
  formStatus.setAttribute("role", "status");
  contactForm.append(formStatus);

  contactForm.addEventListener("submit", (event) => {
    event.preventDefault();

    const nameInput = contactForm.querySelector<HTMLInputElement>("#name");
    const emailInput = contactForm.querySelector<HTMLInputElement>("#email");
    const messageInput = contactForm.querySelector<HTMLTextAreaElement>("#message");
    if (!nameInput || !emailInput || !messageInput) {
      return;
    }

    const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    let isValid = true;

    if (nameInput.value.trim() === "") {
      showError(nameInput, "Please enter your name.");
      isValid = false;
    } else {
      showError(nameInput, "");
    }

    if (!emailPattern.test(emailInput.value.trim())) {
      showError(emailInput, "Please enter a valid email address.");
      isValid = false;
    } else {
      showError(emailInput, "");
    }

    if (messageInput.value.trim().length < 10) {
      showError(messageInput, "Please write at least 10 characters.");
      isValid = false;
    } else {
      showError(messageInput, "");
    }

    if (!isValid) {
      formStatus.textContent = "";
      return;
    }

    formStatus.textContent = `Thanks, ${nameInput.value.trim()}. Your message passed all the checks.`;
    contactForm.reset();
  });
}
