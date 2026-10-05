"use server";

import { redirect } from "next/navigation";
import { endSession, logIn, safeNextPath, signUp, startSession } from "@/lib/auth";

export interface AuthFormState {
  error: string;
}

export async function loginAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await logIn({
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function signupAction(
  _previous: AuthFormState,
  formData: FormData
): Promise<AuthFormState> {
  const result = await signUp({
    name: formData.get("name"),
    email: formData.get("email"),
    password: formData.get("password"),
  });

  if (!result.ok) {
    return { error: result.error };
  }

  await startSession(result.user.id);
  redirect(safeNextPath(formData.get("next")));
}

export async function logoutAction(): Promise<void> {
  await endSession();
  redirect("/");
}
