import type { APIRoute } from "astro";
import { supabase } from "../../lib/supabaseClient";

export const GET: APIRoute = async () => {
  try {
    const { data } = await supabase.rpc("contador_personas");
    return new Response(JSON.stringify({ contador: data ?? 0 }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (_) {
    return new Response(JSON.stringify({ contador: 0 }), { status: 200, headers: { "Content-Type": "application/json" } });
  }
};
