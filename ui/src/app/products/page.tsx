'use client'

import { products } from '@/data/products'
import Image from 'next/image'

export default function ProductsPage() {
  return (
    <div>
      <h1 className="text-4xl font-bold mb-8">Products</h1>
      <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
        {products.map((product) => (
          <div key={product.id} className="border border-gray-200 dark:border-gray-700 rounded-lg overflow-hidden hover:shadow-lg transition-shadow">
            <div className="w-full h-48 bg-gray-100 dark:bg-gray-800 relative">
              <Image
                src={product.image}
                alt={product.name}
                fill
                className="object-cover"
                onError={(e) => {
                  e.currentTarget.style.display = 'none'
                }}
              />
            </div>
            <div className="p-4">
              <p className="text-sm text-indigo-600 dark:text-indigo-400 font-semibold mb-1">
                {product.category}
              </p>
              <h3 className="text-lg font-semibold mb-2">{product.name}</h3>
              <p className="text-gray-600 dark:text-gray-400 text-sm mb-4">
                {product.description}
              </p>
              <div className="flex justify-between items-center">
                <span className="text-2xl font-bold text-indigo-600">
                  ${product.price}
                </span>
                <button className="px-4 py-2 bg-indigo-600 hover:bg-indigo-700 text-white rounded font-semibold transition-colors">
                  Add to Cart
                </button>
              </div>
              {product.stock <= 10 && product.stock > 0 && (
                <p className="mt-2 text-sm text-orange-500">Only {product.stock} left in stock</p>
              )}
              {product.stock === 0 && (
                <p className="mt-2 text-sm text-red-500">Out of stock</p>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
