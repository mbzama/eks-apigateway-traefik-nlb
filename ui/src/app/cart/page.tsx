'use client'

export default function CartPage() {
  return (
    <div className="max-w-2xl mx-auto">
      <h1 className="text-4xl font-bold mb-8">Shopping Cart</h1>
      <div className="bg-gray-50 dark:bg-gray-900 rounded-lg p-8 text-center">
        <p className="text-gray-600 dark:text-gray-400 mb-4">Your cart is empty</p>
        <a
          href="/products"
          className="inline-block px-6 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded font-semibold transition-colors"
        >
          Continue Shopping
        </a>
      </div>
    </div>
  )
}
