import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Digital Commerce',
  description: 'A simple digital commerce web application',
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-gray-50 dark:bg-gray-950">
        <header className="bg-white dark:bg-gray-900 shadow-sm sticky top-0 z-50">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
            <a href="/" className="text-xl font-bold text-indigo-600 dark:text-indigo-400">
              ShopNow
            </a>
            <nav className="flex gap-6 text-sm font-medium text-gray-600 dark:text-gray-300">
              <a href="/" className="hover:text-indigo-600 transition-colors">
                Home
              </a>
              <a href="/products" className="hover:text-indigo-600 transition-colors">
                Products
              </a>
              <a href="/cart" className="hover:text-indigo-600 transition-colors">
                Cart
              </a>
            </nav>
          </div>
        </header>
        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-10">{children}</main>
        <footer className="mt-16 border-t border-gray-200 dark:border-gray-800 py-8 text-center text-sm text-gray-500">
          © {new Date().getFullYear()} ShopNow. All rights reserved.
        </footer>
      </body>
    </html>
  )
}
