#!/usr/bin/env python3
import sys
import pygame


def load_ppm_p3(path: str):
    with open(path, "r", encoding="ascii") as f:
        tokens = []
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            tokens.extend(line.split())

    if tokens[0] != "P3":
        raise ValueError("Only ASCII PPM P3 is supported")

    w = int(tokens[1])
    h = int(tokens[2])
    maxval = int(tokens[3])
    if maxval <= 0:
        raise ValueError("Invalid maxval")

    raw = list(map(int, tokens[4:]))
    if len(raw) < w * h * 3:
        raise ValueError("PPM data is truncated")

    pixels = []
    for i in range(0, w * h * 3, 3):
        r = raw[i]
        g = raw[i + 1]
        b = raw[i + 2]
        pixels.append((r, g, b))

    return w, h, pixels


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "out/frame.ppm"
    w, h, pixels = load_ppm_p3(path)

    pygame.init()
    pygame.display.set_caption("upet_fpga ShellUltra simulation")
    screen = pygame.display.set_mode((w, h))

    surf = pygame.Surface((w, h))
    surf.lock()
    i = 0
    for y in range(h):
        for x in range(w):
            surf.set_at((x, y), pixels[i])
            i += 1
    surf.unlock()

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False

        screen.blit(surf, (0, 0))
        pygame.display.flip()

    pygame.quit()


if __name__ == "__main__":
    main()
