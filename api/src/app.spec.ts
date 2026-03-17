import { Test, TestingModule } from '@nestjs/testing';
import { UsersController } from './users/users.controller';
import { UsersService } from './users/users.service';
import { ProductsController } from './products/products.controller';
import { ProductsService } from './products/products.service';

describe('UsersController', () => {
  let controller: UsersController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [UsersController],
      providers: [UsersService],
    }).compile();
    controller = module.get<UsersController>(UsersController);
  });

  it('should return all users', () => {
    const users = controller.findAll();
    expect(users).toHaveLength(3);
  });

  it('should return a single user', () => {
    const user = controller.findOne(1);
    expect(user.id).toBe(1);
    expect(user.name).toBe('Alice Smith');
  });

  it('should create a user', () => {
    const user = controller.create({ name: 'Dave', email: 'dave@example.com', role: 'user' });
    expect(user.id).toBe(4);
    expect(user.name).toBe('Dave');
  });
});

describe('ProductsController', () => {
  let controller: ProductsController;

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      controllers: [ProductsController],
      providers: [ProductsService],
    }).compile();
    controller = module.get<ProductsController>(ProductsController);
  });

  it('should return all products', () => {
    const products = controller.findAll();
    expect(products).toHaveLength(3);
  });

  it('should return a single product', () => {
    const product = controller.findOne(1);
    expect(product.id).toBe(1);
    expect(product.name).toBe('Laptop Pro');
  });

  it('should create a product', () => {
    const product = controller.create({
      name: 'Keyboard',
      price: 79.99,
      category: 'electronics',
      inStock: true,
    });
    expect(product.id).toBe(4);
  });
});
