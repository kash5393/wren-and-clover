import type { Metadata } from "next";
import { redirect } from "next/navigation";
import AuthForm from "@/components/AuthForm";
import { getCurrentUser, safeNextPath } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Create an account",
};

function first(value: string | string[] | undefined): string {
  return Array.isArray(value) ? (value[0] ?? "") : (value ?? "");
}

export default async function SignupPage(props: PageProps<"/signup">) {
  const query = await props.searchParams;
  const nextPath = safeNextPath(first(query.next));

  if (await getCurrentUser()) {
    redirect(nextPath);
  }

  return (
    <section className="section">
      <div className="container prose">
        <h1 className="page-title">Create an account</h1>
        <AuthForm mode="signup" nextPath={nextPath} defaultEmail={first(query.email)} />
      </div>
    </section>
  );
}
