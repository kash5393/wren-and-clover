"use strict";
const form = document.querySelector(".contact-form");
function showError(field, message) {
    let error = field.parentElement.querySelector(".field-error");
    if (!error) {
        error = document.createElement("span");
        error.className = "field-error";
        field.parentElement.append(error);
    }
    error.textContent = message;
    field.setAttribute("aria-invalid", message ? "true" : "false");
}
if (form) {
    form.noValidate = true;
    const status = document.createElement("p");
    status.className = "form-status";
    status.setAttribute("role", "status");
    form.append(status);
    form.addEventListener("submit", (event) => {
        event.preventDefault();
        const name = form.querySelector("#name");
        const email = form.querySelector("#email");
        const message = form.querySelector("#message");
        const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        let isValid = true;
        if (name.value.trim() === "") {
            showError(name, "Please enter your name.");
            isValid = false;
        }
        else {
            showError(name, "");
        }
        if (!emailPattern.test(email.value.trim())) {
            showError(email, "Please enter a valid email address.");
            isValid = false;
        }
        else {
            showError(email, "");
        }
        if (message.value.trim().length < 10) {
            showError(message, "Please write at least 10 characters.");
            isValid = false;
        }
        else {
            showError(message, "");
        }
        if (!isValid) {
            status.textContent = "";
            return;
        }
        status.textContent = `Thanks, ${name.value.trim()}. Your message passed all the checks.`;
        form.reset();
    });
}
