interface Product {
  id: number
  name: string
  price: number
  category: string
  inStock: boolean
}

async function getProducts(): Promise<Product[]> {
  const url = process.env.API_URL
    ? `${process.env.API_URL}/api/products`
    : 'http://mock-api.mock-api.svc.cluster.local/api/products'

  const res = await fetch(url, { cache: 'no-store' })
  if (!res.ok) throw new Error(`Failed to fetch products: ${res.status}`)
  return res.json()
}

export default async function ProductsPage() {
  const products = await getProducts()

  return (
    <div>
      <h1 className="text-4xl font-bold mb-8">Products</h1>
      <div className="overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700">
        <table className="w-full text-sm text-left">
          <thead className="bg-gray-50 dark:bg-gray-800 text-gray-600 dark:text-gray-300 uppercase text-xs">
            <tr>
              <th className="px-6 py-3">ID</th>
              <th className="px-6 py-3">Name</th>
              <th className="px-6 py-3">Category</th>
              <th className="px-6 py-3">Price</th>
              <th className="px-6 py-3">In Stock</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200 dark:divide-gray-700">
            {products.map((product) => (
              <tr key={product.id} className="bg-white dark:bg-gray-900 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors">
                <td className="px-6 py-4 text-gray-500">{product.id}</td>
                <td className="px-6 py-4 font-medium text-gray-900 dark:text-white">{product.name}</td>
                <td className="px-6 py-4">
                  <span className="px-2 py-1 text-xs font-semibold rounded-full bg-indigo-100 text-indigo-700 dark:bg-indigo-900 dark:text-indigo-300">
                    {product.category}
                  </span>
                </td>
                <td className="px-6 py-4 font-semibold text-indigo-600">${product.price.toFixed(2)}</td>
                <td className="px-6 py-4">
                  {product.inStock ? (
                    <span className="px-2 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-700 dark:bg-green-900 dark:text-green-300">
                      In Stock
                    </span>
                  ) : (
                    <span className="px-2 py-1 text-xs font-semibold rounded-full bg-red-100 text-red-700 dark:bg-red-900 dark:text-red-300">
                      Out of Stock
                    </span>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  )
}
