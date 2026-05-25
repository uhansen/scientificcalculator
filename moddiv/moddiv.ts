import type * as ModdivInterface from "./types/interfaces/buildbyhansen-moddiv-moddiv.js";

type ModdivExport = typeof ModdivInterface;

export const moddiv: ModdivExport = {
  mod(x: number, y: number): number {
    return x % y;
  },

  div(x: number, y: number): number {
    return x / y;
  },
};
