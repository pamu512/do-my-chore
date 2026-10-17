import "https://deno.land/std@0.224.0/http/server.ts";
import { handlePaypalCapture } from "../_shared/wallet_http.ts";

Deno.serve((req) => handlePaypalCapture(req));
