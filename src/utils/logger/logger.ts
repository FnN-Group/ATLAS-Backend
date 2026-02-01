import chalk from "chalk";

export default {
  backend(...messages: string[]) {
    console.log(`\x1b[37m[\x1b[96mBACKEND\x1b[0m\x1b[37m]`, ...messages);
  },

  startup(...messages: string[]) {
    console.log(`\x1b[32m[STARTUP]\x1b[0m`, ...messages);
  },

  bot(...messages: string[]) {
    console.log(`\x1b[36m[BOT]\x1b[0m`, ...messages);
  },

  debug(...messages: string[]) {
    console.log(`\x1b[35m[DEBUG]\x1b[0m`, ...messages);
  },

  error(...messages: string[]) {
    console.error(`\x1b[31m[ERROR]\x1b[0m`, ...messages);
  },
  
  info(...messages: string[]) {
    if (messages.length > 0 && typeof messages[0] === 'string') {
      const first = messages[0].trim();
      if (first.startsWith('[')) {
        console.log(...messages);
        return;
      }
    }
    console.log(`\x1b[34m[INFO]\x1b[0m`, ...messages);
  },
  
  success(...messages: string[]) {
    console.log(`\x1b[32m[SUCCESS]\x1b[0m`, ...messages);
  },
  
  warning(...messages: string[]) {
    console.log(`\x1b[33m[WARNING]\x1b[0m`, ...messages);
  },
};