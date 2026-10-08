export interface Deal {
  title: string;
  url: string;
  price?: number;
  snippet?: string;
  source: string;
}

export function extractUsdPrice(text: string): number | undefined {
  const m = text.match(/\$([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?)/);
  if (!m) return undefined;
  const n = Number(m[1].replaceAll(",", ""));
  return Number.isFinite(n) ? n : undefined;
}

export function dealsUnderBudget(deals: Deal[], budget: number): Deal[] {
  const priced = deals.filter((d) => d.price != null && d.price <= budget + 1e-9);
  if (priced.length) return priced.slice(0, 3);
  if (deals.some((d) => d.price != null)) return [];
  return deals.slice(0, 3);
}

/** Optional Tavily search. Missing key or any error → empty + skipped. */
export async function searchDeals(
  query: string,
  budget: number,
): Promise<{ deals: Deal[]; dealSearch: "tavily" | "skipped" }> {
  const key = Deno.env.get("TAVILY_API_KEY")?.trim();
  if (!key) return { deals: [], dealSearch: "skipped" };
  try {
    const res = await fetch("https://api.tavily.com/search", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        query,
        max_results: 5,
        search_depth: "basic",
      }),
    });
    if (!res.ok) return { deals: [], dealSearch: "skipped" };
    const data = await res.json();
    const raw = Array.isArray(data?.results) ? data.results : [];
    const mapped: Deal[] = raw.map((r: { title?: string; url?: string; content?: string }) => {
      const snippet = String(r.content ?? "");
      const price = extractUsdPrice(`${r.title ?? ""} ${snippet}`);
      return {
        title: String(r.title ?? "Deal"),
        url: String(r.url ?? ""),
        snippet: snippet.slice(0, 240) || undefined,
        source: "tavily",
        ...(price != null ? { price } : {}),
      };
    }).filter((d: Deal) => d.url);
    return { deals: dealsUnderBudget(mapped, budget), dealSearch: "tavily" };
  } catch {
    return { deals: [], dealSearch: "skipped" };
  }
}
