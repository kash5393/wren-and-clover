import { createContext, useContext, useEffect, useState } from "react";
import type { ReactNode } from "react";
import type { User } from "../types";

interface AuthContextValue {
  user: User | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<string | null>;
  signup: (name: string, email: string, password: string) => Promise<string | null>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

interface AuthResponse {
  user?: User;
  error?: string;
}

async function postJson(url: string, body: unknown): Promise<AuthResponse> {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return (await response.json()) as AuthResponse;
  } catch (error) {
    console.error(error);
    return { error: "Could not reach the shop. Please try again." };
  }
}

interface AuthProviderProps {
  children: ReactNode;
}

export function AuthProvider({ children }: AuthProviderProps) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function loadCurrentUser() {
      try {
        const response = await fetch("/api/auth/me");
        const data = (await response.json()) as AuthResponse;
        if (!cancelled) {
          setUser(response.ok && data.user ? data.user : null);
        }
      } catch (error) {
        console.error(error);
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadCurrentUser();

    return () => {
      cancelled = true;
    };
  }, []);

  async function login(email: string, password: string) {
    const data = await postJson("/api/auth/login", { email, password });
    if (data.user) {
      setUser(data.user);
      return null;
    }
    return data.error ?? "Could not sign in.";
  }

  async function signup(name: string, email: string, password: string) {
    const data = await postJson("/api/auth/signup", { name, email, password });
    if (data.user) {
      setUser(data.user);
      return null;
    }
    return data.error ?? "Could not create the account.";
  }

  async function logout() {
    try {
      await fetch("/api/auth/logout", { method: "POST" });
    } catch (error) {
      console.error(error);
    }
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, loading, login, signup, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used inside an AuthProvider");
  }
  return context;
}
