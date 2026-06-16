import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { createBrowserRouter, RouterProvider } from "react-router"
import Home, { loader as homeLoader } from "./routes/home"
import "./index.css"

const router = createBrowserRouter([
  {
    path: "/",
    element: <Home />,
    loader: homeLoader,
  },
])

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <RouterProvider router={router} />
  </StrictMode>
)
