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
