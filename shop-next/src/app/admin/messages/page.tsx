import type { Metadata } from "next";
import { getMessages } from "@/lib/admin";
import { requireOwner } from "@/lib/auth";

export const metadata: Metadata = {
  title: "Messages",
};

export default async function AdminMessagesPage() {
  await requireOwner();
  const messages = await getMessages();

  return (
    <>
      <h1 className="page-title">Messages</h1>

      {messages.length === 0 ? (
        <p>No messages yet.</p>
      ) : (
        <div className="order-list">
          {messages.map((message) => (
            <article className="order-card" key={message.id}>
              <header className="order-card-header">
                <h2>{message.name}</h2>
                <p>{message.createdAt.slice(0, 10)}</p>
              </header>
              <p className="order-customer">
                <a href={`mailto:${message.email}`}>{message.email}</a>
              </p>
              <p className="order-customer">{message.message}</p>
            </article>
          ))}
        </div>
      )}
    </>
  );
}
