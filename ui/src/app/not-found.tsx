export default function NotFound() {
  return (
    <div className="min-h-[400px] flex flex-col items-center justify-center text-center">
      <h1 className="text-6xl font-bold mb-4">404</h1>
      <p className="text-2xl text-gray-600 dark:text-gray-400 mb-8">Page not found</p>
      <a
        href="/"
        className="px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded font-semibold transition-colors"
      >
        Go Home
      </a>
    </div>
  )
}
