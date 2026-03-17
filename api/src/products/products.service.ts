import { Injectable, NotFoundException } from '@nestjs/common';

export interface Product {
  id: number;
  name: string;
  price: number;
  category: string;
  inStock: boolean;
}

@Injectable()
export class ProductsService {
  private products: Product[] = [
    { id: 1, name: 'Laptop Pro', price: 1299.99, category: 'electronics', inStock: true },
    { id: 2, name: 'Wireless Mouse', price: 29.99, category: 'electronics', inStock: true },
    { id: 3, name: 'Standing Desk', price: 499.0, category: 'furniture', inStock: false },
  ];

  findAll(): Product[] {
    return this.products;
  }

  findOne(id: number): Product {
    const product = this.products.find((p) => p.id === id);
    if (!product) throw new NotFoundException(`Product #${id} not found`);
    return product;
  }

  create(dto: Omit<Product, 'id'>): Product {
    const product: Product = { id: this.products.length + 1, ...dto };
    this.products.push(product);
    return product;
  }

  update(id: number, dto: Partial<Omit<Product, 'id'>>): Product {
    const product = this.findOne(id);
    Object.assign(product, dto);
    return product;
  }

  remove(id: number): void {
    const index = this.products.findIndex((p) => p.id === id);
    if (index === -1) throw new NotFoundException(`Product #${id} not found`);
    this.products.splice(index, 1);
  }
}
