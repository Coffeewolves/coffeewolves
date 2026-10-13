import { getApp, getApps, initializeApp } from
  "https://www.gstatic.com/firebasejs/10.14.1/firebase-app.js";
import {
  getAuth,
  onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-auth.js";
import {
  addDoc,
  collection,
  getFirestore,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/10.14.1/firebase-firestore.js";

const firebaseConfig = {
  apiKey: "AIzaSyCXs0XqqOS0WJwvZwMreagmG8UWZM1Anqg",
  appId: "1:639914979018:web:fbcf5b96118deefc308e33",
  messagingSenderId: "639914979018",
  projectId: "wolves-club-fb24a",
  authDomain: "wolves-club-fb24a.firebaseapp.com",
  storageBucket: "wolves-club-fb24a.firebasestorage.app",
};

const app = getApps().length ? getApp() : initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

const form = document.querySelector("#support-form");
const authNotice = document.querySelector("#auth-notice");
const formMessage = document.querySelector("#form-message");
const submitButton = document.querySelector("#submit-button");
const fileInput = document.querySelector("#screenshot");
const fileLabel = document.querySelector("#file-label");
const preview = document.querySelector("#image-preview");
const receipt = document.querySelector("#receipt");
const caseId = document.querySelector("#case-id");
let currentUser = null;
let selectedImage = null;

function setNotice(message, state) {
  authNotice.textContent = message;
  authNotice.dataset.state = state;
}

function updateSubmitState() {
  submitButton.disabled =
    !currentUser ||
    !currentUser.emailVerified ||
    !form.checkValidity();
}

onAuthStateChanged(auth, async (user) => {
  currentUser = user;
  if (user) {
    try {
      await user.reload();
      const refreshedUser = auth.currentUser;
      if (!refreshedUser || refreshedUser.uid !== user.uid) {
        currentUser = null;
        setNotice("La sesión terminó. Inicia sesión nuevamente.", "error");
        updateSubmitState();
        return;
      }
      await refreshedUser.getIdToken(true);
      currentUser = refreshedUser;
    } catch (error) {
      console.error("No se pudo actualizar la sesión de soporte:", error);
      currentUser = null;
      setNotice(
        "No se pudo comprobar tu sesión. Recarga la página e inténtalo de nuevo.",
        "error",
      );
      updateSubmitState();
      return;
    }
  }
  const userIdInput = document.querySelector("#user-id");
  if (user?.emailVerified) {
    userIdInput.value = user.uid;
    setNotice(`Sesión verificada: ${user.email}`, "ready");
  } else {
    userIdInput.value = "";
    setNotice(
      user
        ? "Confirma tu correo antes de enviar un mensaje de soporte."
        : "Inicia sesión en Coffee Wolves para completar el formulario.",
      "error",
    );
  }
  updateSubmitState();
});

form.addEventListener("input", updateSubmitState);
form.addEventListener("change", updateSubmitState);

fileInput.addEventListener("change", () => {
  const file = fileInput.files?.[0] ?? null;
  selectedImage = file;
  fileLabel.textContent = file?.name ?? "Selecciona una imagen JPG, PNG o WebP";
  if (file) {
    preview.src = URL.createObjectURL(file);
    preview.classList.add("is-visible");
  } else {
    preview.removeAttribute("src");
    preview.classList.remove("is-visible");
  }
});

async function compressScreenshot(file) {
  if (!file.type.startsWith("image/")) {
    throw new Error("El archivo debe ser una imagen.");
  }

  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1440 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(bitmap.width * scale));
  canvas.height = Math.max(1, Math.round(bitmap.height * scale));
  const context = canvas.getContext("2d");
  if (!context) throw new Error("No se pudo procesar la captura.");
  context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();

  let blob = null;
  for (const quality of [0.78, 0.66, 0.54, 0.42]) {
    blob = await new Promise((resolve) =>
      canvas.toBlob(resolve, "image/jpeg", quality),
    );
    if (blob && blob.size <= 450_000) break;
  }
  if (!blob || blob.size > 450_000) {
    throw new Error("La captura es demasiado grande. Prueba con otra imagen.");
  }

  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return {
    base64: btoa(binary),
    contentType: "image/jpeg",
    name: `${file.name.replace(/[^\w.-]/g, "_").slice(0, 110)}.jpg`,
  };
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  formMessage.textContent = "";
  if (!form.reportValidity()) return;

  submitButton.disabled = true;
  submitButton.querySelector(".button-label").textContent = "Enviando…";
  try {
    const initialUser = currentUser;
    if (!initialUser) {
      throw new Error("Inicia sesión con tu correo verificado para enviar el caso.");
    }
    await initialUser.reload();
    const verifiedUser = auth.currentUser;
    if (!verifiedUser || verifiedUser.uid !== initialUser.uid) {
      throw new Error("La sesión terminó. Inicia sesión nuevamente.");
    }
    await verifiedUser.getIdToken(true);
    if (!verifiedUser.emailVerified) {
      throw new Error("Confirma tu correo antes de enviar el caso.");
    }
    currentUser = verifiedUser;
    const attachment = selectedImage
      ? await compressScreenshot(selectedImage)
      : null;
    const category = document.querySelector("#category").value;
    const subject = document.querySelector("#subject").value.trim();
    const details = document.querySelector("#details").value.trim();
    const data = {
      customerUid: verifiedUser.uid,
      customerEmail: verifiedUser.email,
      shift: "morning",
      incident: category,
      feedbackType: "complaint",
      supportCategory: category,
      subject,
      details,
      autoReply:
        "Recibimos tu reclamo. Gerencia revisará el caso y podrás consultar aquí su estado.",
      statusMessage: "Tu mensaje fue recibido y está pendiente de revisión.",
      createdAt: serverTimestamp(),
      status: "new",
    };
    if (attachment) {
      data.attachmentBase64 = attachment.base64;
      data.attachmentContentType = attachment.contentType;
      data.attachmentName = attachment.name;
    }

    const savedCase = await addDoc(collection(db, "customerComplaints"), data);
    caseId.textContent = savedCase.id;
    form.hidden = true;
    receipt.hidden = false;
  } catch (error) {
    console.error("No se pudo enviar el caso de soporte:", error);
    formMessage.textContent =
      error?.code === "permission-denied"
        ? "No se pudo autorizar el envío. Confirma que tu cuenta tenga el correo verificado."
        : error?.message ?? "No se pudo enviar el mensaje. Inténtalo de nuevo.";
    submitButton.disabled = false;
    submitButton.querySelector(".button-label").textContent = "Enviar a soporte";
    updateSubmitState();
  }
});

document.querySelector("#new-case").addEventListener("click", () => {
  form.reset();
  selectedImage = null;
  preview.removeAttribute("src");
  preview.classList.remove("is-visible");
  fileLabel.textContent = "Selecciona una imagen JPG, PNG o WebP";
  receipt.hidden = true;
  form.hidden = false;
  formMessage.textContent = "";
  submitButton.querySelector(".button-label").textContent = "Enviar a soporte";
  updateSubmitState();
});
