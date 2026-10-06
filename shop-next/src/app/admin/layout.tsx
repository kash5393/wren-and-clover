import type { Metadata } from "next";
import Link from "next/link";
import type { ReactNode } from "react";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: {
    default: "Admin",
    template: "%s | Admin | Wren & Clover",
  },
  robots: { index: false },
};

interface AdminLayoutProps {
  children: ReactNode;
}

export default async function AdminLayout({ children }: AdminLayoutProps) {
  const owner = await requireOwner();

  return (
    <section className="section">
      <div className="container">
        <p className="admin-signed-in">Admin area, signed in as {owner.name}</p>
        <nav className="filters" aria-label="Admin">
          <Link className="chip" href="/admin">Dashboard</Link>
          <Link className="chip" href="/admin/products">Products</Link>
          <Link className="chip" href="/admin/orders">Orders</Link>
          <Link className="chip" href="/admin/messages">Messages</Link>
          <Link className="chip" href="/admin/settings">Settings</Link>
        </nav>
        {children}
      </div>
    </section>
  );
}
