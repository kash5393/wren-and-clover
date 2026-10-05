import type { Metadata } from "next";
import { redirect } from "next/navigation";
import AuthForm from "@/components/AuthForm";
import { getCurrentUser, safeNextPath } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Sign in",
};

function first(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

export default async function LoginPage(props: PageProps<"/login">) {
  const query = await props.searchParams;
  const nextPath = safeNextPath(first(query.next));

  if (await getCurrentUser()) {
    redirect(nextPath);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Sign in</h1>
        <AuthForm mode="login" nextPath={nextPath} defaultEmail={first(query.email)} />
      </div>
    </section>
  );
}
