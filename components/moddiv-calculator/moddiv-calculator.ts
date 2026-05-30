import type * as ModdivInterface from "./types/interfaces/buildbyhansen-moddiv-calculator-moddiv.js";

type ModdivExport = typeof ModdivInterface;

//modulus operation and division operation calculator
export const moddiv: ModdivExport = {
  mod(x: number, y: number): number {
    return x % y;
  },

  div(x: number, y: number): number {
    return x / y;
  },
};
