'use client'

export default function Home() {
  return (
    <div className="space-y-12">
      <section className="text-center py-12">
        <h1 className="text-5xl font-bold text-gray-900 dark:text-white mb-4">
          Welcome to ShopNow
        </h1>
        <p className="text-xl text-gray-600 dark:text-gray-300 mb-8">
          Your digital marketplace for premium products
        </p>
        <a
          href="/products"
          className="inline-block px-8 py-3 bg-indigo-600 hover:bg-indigo-700 text-white font-semibold rounded-lg transition-colors"
        >
          Shop Now
        </a>
      </section>

      <section className="grid md:grid-cols-3 gap-8">
        <div className="p-6 border border-gray-200 dark:border-gray-700 rounded-lg">
          <h3 className="text-lg font-semibold mb-2">🚚 Fast Delivery</h3>
          <p className="text-gray-600 dark:text-gray-400">
            Get your products delivered to your doorstep within 24-48 hours
          </p>
        </div>
        <div className="p-6 border border-gray-200 dark:border-gray-700 rounded-lg">
          <h3 className="text-lg font-semibold mb-2">✅ Quality Guaranteed</h3>
          <p className="text-gray-600 dark:text-gray-400">
            All products are carefully selected and quality-checked
          </p>
        </div>
        <div className="p-6 border border-gray-200 dark:border-gray-700 rounded-lg">
          <h3 className="text-lg font-semibold mb-2">💳 Secure Payment</h3>
          <p className="text-gray-600 dark:text-gray-400">
            Your payment information is encrypted and secure
          </p>
        </div>
      </section>
    </div>
  )
}
