import { useEffect, useState } from "react";
import { doc, onSnapshot, type Timestamp } from "firebase/firestore";
import { getFunctions, httpsCallable } from "firebase/functions";
import { app, auth, db } from "./firebase";

type BillingLink = { url: string };

export type VoyagePassEntitlement = {
  active: boolean;
  loading: boolean;
  status: string;
  cancelAtPeriodEnd: boolean;
  currentPeriodEnd: Date | null;
};

const EMPTY_PASS: VoyagePassEntitlement = {
  active: false,
  loading: true,
  status: "none",
  cancelAtPeriodEnd: false,
  currentPeriodEnd: null,
};

export function useVoyagePass(): VoyagePassEntitlement {
  const [pass, setPass] = useState<VoyagePassEntitlement>(EMPTY_PASS);
  const uid = auth.currentUser?.uid;

  useEffect(() => {
    if (!uid) {
      setPass({ ...EMPTY_PASS, loading: false });
      return;
    }
    return onSnapshot(
      doc(db, "users", uid, "entitlements", "voyagePass"),
      (snapshot) => {
        const value = snapshot.data();
        const periodEnd = value?.currentPeriodEnd as Timestamp | null | undefined;
        setPass({
          active: value?.active === true,
          loading: false,
          status: typeof value?.status === "string" ? value.status : "none",
          cancelAtPeriodEnd: value?.cancelAtPeriodEnd === true,
          currentPeriodEnd: periodEnd?.toDate?.() ?? null,
        });
      },
      () => setPass({ ...EMPTY_PASS, loading: false }),
    );
  }, [uid]);

  return pass;
}

async function openBillingLink(name: "createVoyagePassCheckout" | "createVoyagePassPortal") {
  const functions = getFunctions(app, "asia-northeast1");
  const invoke = httpsCallable<void, BillingLink>(functions, name);
  const result = await invoke();
  if (!result.data.url.startsWith("https://")) throw new Error("Invalid billing URL");
  window.location.assign(result.data.url);
}

export function startVoyagePassCheckout() {
  return openBillingLink("createVoyagePassCheckout");
}

export function openVoyagePassPortal() {
  return openBillingLink("createVoyagePassPortal");
}
