// Regeln für Sealed Sender im Firestore-Emulator prüfen:
//   cd firebase/rules-tests && npm install && npm test
// Die Firebase-CLI bringt ihr eigenes Node mit, das keine ES-Module lädt —
// deshalb ruft das Skript ausdrücklich das Node aus dem PATH auf.
import { initializeTestEnvironment, assertSucceeds, assertFails } from "@firebase/rules-unit-testing";
import { doc, setDoc, addDoc, getDoc, deleteDoc, collection, serverTimestamp, Bytes } from "firebase/firestore";
import { readFileSync } from "node:fs";
import { createHash, randomBytes } from "node:crypto";

const env = await initializeTestEnvironment({
  projectId: "demo-krypta",
  // Host und Port setzt `firebase emulators:exec` (FIRESTORE_EMULATOR_HOST).
  firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
});
const BOB = "bobUid0000000000000002", ALICE = "aliceUid00000000000001", EVE = "eveUid0000000000000003";
const key = randomBytes(32), wrong = randomBytes(32);
const b = (buf) => Bytes.fromUint8Array(new Uint8Array(buf));
const bob = env.authenticatedContext(BOB).firestore();
const alice = env.authenticatedContext(ALICE).firestore();
const eve = env.authenticatedContext(EVE).firestore();
const anon = env.unauthenticatedContext().firestore();
const inbox = (db, uid = BOB) => collection(db, "messages", uid, "inbox");
const sealed = (ak, extra = {}) => ({ p: { s: "dW1zY2hsYWc=", nt: "AAAA" }, ts: serverTimestamp(), ak: b(ak), ...extra });
let failures = 0;
async function check(name, p) {
  try { await p; console.log("ok   ", name); } catch (e) { failures++; console.log("FAIL ", name, "-", e.message.split("\n")[0]); }
}

await check("Eigentümer legt Hash ab", assertSucceeds(setDoc(doc(bob, "sealedAccess", BOB), { h: b(createHash("sha256").update(key).digest()), updatedAt: serverTimestamp() })));
await check("Fremder darf Hash nicht setzen", assertFails(setDoc(doc(eve, "sealedAccess", BOB), { h: b(createHash("sha256").update(wrong).digest()), updatedAt: serverTimestamp() })));
await check("Hash falscher Länge abgelehnt", assertFails(setDoc(doc(bob, "sealedAccess", BOB), { h: b(randomBytes(16)), updatedAt: serverTimestamp() })));
await check("Hash ist nicht lesbar", assertFails(getDoc(doc(eve, "sealedAccess", BOB))));
await check("Hash auch für Eigentümer nicht lesbar", assertFails(getDoc(doc(bob, "sealedAccess", BOB))));

await check("Versiegelt ohne Anmeldung, richtiger Schlüssel", assertSucceeds(addDoc(inbox(anon), sealed(key))));
await check("Versiegelt, falscher Schlüssel", assertFails(addDoc(inbox(anon), sealed(wrong))));
await check("Versiegelt, aber mit sid", assertFails(addDoc(inbox(anon), sealed(key, { sid: ALICE }))));
await check("Versiegelt, mit mid", assertFails(addDoc(inbox(anon), sealed(key, { mid: "12345678" }))));
await check("Versiegelt, ohne ak", assertFails(addDoc(inbox(anon), { p: { s: "eA==" }, ts: serverTimestamp() })));
await check("Versiegelt, fremdes Feld in p", assertFails(addDoc(inbox(anon), { p: { s: "eA==", c: "x" }, ts: serverTimestamp(), ak: b(key) })));
await check("Versiegelt, Zeit gefälscht", assertFails(addDoc(inbox(anon), { ...sealed(key), ts: new Date(0) })));
await check("Versiegelt an Empfänger ohne Eintrag", assertFails(addDoc(inbox(anon, EVE), sealed(key))));
await check("Versiegelt, auch angemeldet erlaubt", assertSucceeds(addDoc(inbox(alice), sealed(key))));

const legacy = { sid: ALICE, mid: "12345678-abcd", p: { v: 3, c: "x" }, ts: serverTimestamp() };
await check("Mit Absender, angemeldet", assertSucceeds(addDoc(inbox(alice), legacy)));
await check("Mit Absender, fremde sid", assertFails(addDoc(inbox(eve), legacy)));
await check("Mit Absender, ohne Anmeldung", assertFails(addDoc(inbox(anon), legacy)));

// Löschen
async function seed(data) { let ref; await env.withSecurityRulesDisabled(async (ctx) => { ref = await addDoc(inbox(ctx.firestore()), data); }); return ref; }
const sealedRef = await seed({ p: { s: "eA==" }, ts: new Date(), ak: b(key) });
const legacyRef = await seed({ ...legacy, ts: new Date() });
await check("Mit Absender: Fremder löscht nicht (ohne Anmeldung)", assertFails(deleteDoc(doc(anon, legacyRef.path))));
await check("Mit Absender: Fremder löscht nicht (angemeldet)", assertFails(deleteDoc(doc(eve, legacyRef.path))));
await check("Mit Absender: Absender löscht eigene", assertSucceeds(deleteDoc(doc(alice, legacyRef.path))));
await check("Versiegelt: Absender löscht ohne Anmeldung", assertSucceeds(deleteDoc(doc(anon, sealedRef.path))));

// Lesen
await check("Empfänger liest Posteingang", assertSucceeds(getDoc(doc(bob, "messages", BOB, "inbox", "x"))));
await check("Ohne Anmeldung kein Lesen", assertFails(getDoc(doc(anon, "messages", BOB, "inbox", "x"))));
await check("Fremder liest nicht", assertFails(getDoc(doc(eve, "messages", BOB, "inbox", "x"))));
const sealed2 = await seed({ p: { s: "eA==" }, ts: new Date(), ak: b(key) });
await check("Empfänger löscht Versiegeltes", assertSucceeds(deleteDoc(doc(bob, sealed2.path))));

await env.cleanup();
console.log(failures === 0 ? "ALLE REGELN OK" : `${failures} FEHLER`);
process.exit(failures === 0 ? 0 : 1);
