# Mock Web

A modern e-commerce web application built with [Next.js](https://nextjs.org/), TypeScript, and Tailwind CSS.

---

## Prerequisites

- [Node.js](https://nodejs.org/) >= 22.0.0
- [pnpm](https://pnpm.io/) >= 9.0.0
- [Docker](https://www.docker.com/) (for containerised runs)

---

## Running Locally

### 1. Install dependencies

```bash
pnpm install
```

### 2. Configure environment variables

```bash
cp .env.example .env.local
```

Edit `.env.local` and fill in the required values.

### 3. Start the development server

```bash
pnpm dev
```

The app will be available at [http://localhost:3000](http://localhost:3000).

### Other useful commands

| Command | Description |
|---|---|
| `pnpm build` | Build for production |
| `pnpm start` | Start the production server |
| `pnpm lint` | Run ESLint and type checks |
| `pnpm format` | Format code with Prettier |
| `pnpm test` | Run tests once |
| `pnpm test:watch` | Run tests in watch mode |
| `pnpm test:coverage` | Run tests with coverage report |

---

## Running with Docker

### Build the image

```bash
docker buildx build --platform linux/amd64 -t mock-web .
```

> `--platform linux/amd64` is required when building on Apple Silicon (arm64) for deployment to x86_64 hosts (e.g. EKS t3.medium nodes). Omitting it produces an arm64 image that will fail with `no match for platform in manifest: not found`.

### Run the container

```bash
docker run -p 3000:3000 mock-web
```

The app will be available at [http://localhost:3000](http://localhost:3000).

### Pass environment variables

```bash
docker run -p 3000:3000 \
  -e NEXT_PUBLIC_API_URL=https://api.example.com \
  mock-web
```

Or use an env file:

```bash
docker run -p 3000:3000 --env-file .env.local mock-web
```

### Using Docker Compose

```bash
docker compose up --build
```

To run in detached mode:

```bash
docker compose up --build -d
```

To stop:

```bash
docker compose down
```

---

## Project Structure

```
src/
├── app/          # Next.js App Router pages and layouts
├── components/   # Reusable UI components
├── data/         # Static/mock data
├── types/        # TypeScript type definitions
└── test/         # Test setup and utilities
```

---

## Deployment

### Deploy to Docker Hub

The `deploy.sh` script builds the Docker image and pushes it to Docker Hub.

**Prerequisites:**
- Docker Hub account
- `docker` CLI configured with your credentials

**Usage:**

```bash
# Set your Docker Hub username
export DOCKERHUB_USERNAME=your-username

# Optional: customize image name and tag (defaults: mock-web:latest)
export IMAGE_NAME=my-app
export IMAGE_TAG=v1.0.0

# Run the deployment script
./deploy.sh
```

The script will:
1. Build the Docker image for `linux/amd64` using `docker buildx`
2. Push both the versioned tag and `latest` to Docker Hub in a single step
3. Output the full image reference (e.g., `your-username/mock-web:latest`)

You can then pull and run the image from any environment:

```bash
docker run -p 3000:3000 your-username/mock-web:latest
```

---

## Tech Stack

- **Framework**: [Next.js 16](https://nextjs.org/)
- **Language**: [TypeScript](https://www.typescriptlang.org/)
- **Styling**: [Tailwind CSS 4](https://tailwindcss.com/)
- **Testing**: [Vitest](https://vitest.dev/) + [Testing Library](https://testing-library.com/)
- **Linting**: [ESLint](https://eslint.org/) + [Prettier](https://prettier.io/)
- **Package Manager**: [pnpm](https://pnpm.io/)

---
