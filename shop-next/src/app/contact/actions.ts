"use server";

import { z } from "zod";
import { pool } from "@/lib/db";

const messageSchema = z.object({
  name: z.string().trim().min(1, "Please enter your name."),
  email: z.email("Please enter a valid email address."),
  message: z.string().trim().min(10, "Please write at least 10 characters."),
});

export interface ContactState {
  status: "idle" | "sent" | "error";
  sentTo?: string;
  errors?: { name?: string; email?: string; message?: string };
}

export async function sendMessage(
  _previous: ContactState,
  formData: FormData
): Promise<ContactState> {
  const parsed = messageSchema.safeParse({
    name: formData.get("name"),
    email: formData.get("email"),
    message: formData.get("message"),
  });

  if (!parsed.success) {
    const errors: ContactState["errors"] = {};
    for (const issue of parsed.error.issues) {
      const field = issue.path[0];
      if (field === "name" || field === "email" || field === "message") {
        errors[field] ??= issue.message;
      }
    }
    return { status: "error", errors };
  }

  await pool.query(
    "INSERT INTO contact_messages (name, email, message) VALUES ($1, $2, $3)",
    [parsed.data.name, parsed.data.email, parsed.data.message]
  );

  return { status: "sent", sentTo: parsed.data.name };
}
