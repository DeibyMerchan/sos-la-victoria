import { defineMiddleware } from "astro:middleware";
import { createClient } from "@supabase/supabase-js";

const supabaseUrl = import.meta.env.PUBLIC_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.PUBLIC_SUPABASE_ANON_KEY;

export const onRequest = defineMiddleware(async (context, next) => {
  const { url, cookies, request } = context;

  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": url.origin,
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
        "Access-Control-Allow-Credentials": "true",
      },
    });
  }

  if (url.pathname.startsWith("/admin") && url.pathname !== "/admin/login") {
    const accessToken = cookies.get("sb-access-token")?.value;
    const refreshToken = cookies.get("sb-refresh-token")?.value;

    if (!accessToken || !refreshToken) {
      return context.redirect("/admin/login");
    }

    try {
      const supabase = createClient(supabaseUrl, supabaseAnonKey);
      const { data } = await supabase.auth.setSession({
        access_token: accessToken,
        refresh_token: refreshToken,
      });

      if (!data.user) {
        return context.redirect("/admin/login");
      }
    } catch {
      return context.redirect("/admin/login");
    }
  }

  const response = await next();

  response.headers.set("Access-Control-Allow-Origin", url.origin);
  response.headers.set("Access-Control-Allow-Credentials", "true");

  return response;
});
