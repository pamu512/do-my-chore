import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dealsUnderBudget, extractUsdPrice } from "./deals.ts";

Deno.test("extractUsdPrice reads the first dollar amount", () => {
  assertEquals(extractUsdPrice("From $2,899 for a family of four"), 2899);
  assertEquals(extractUsdPrice("about $199.99 plus tax"), 199.99);
  assertEquals(extractUsdPrice("no price here"), undefined);
});

Deno.test("dealsUnderBudget keeps priced deals at or under budget", () => {
  const kept = dealsUnderBudget([
    { title: "Over", url: "https://a.example", price: 4000, source: "tavily" },
    { title: "Fit", url: "https://b.example", price: 2899, source: "tavily" },
  ], 3500);
  assertEquals(kept.map((d) => d.title), ["Fit"]);
});
