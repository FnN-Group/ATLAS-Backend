// Simple Discord RPC test script
import DiscordRPC from 'discord-rpc';
import { execSync } from 'child_process';

const clientId = '1469880369573658645';

console.log('Testing Discord RPC connection...');
console.log('Client ID:', clientId);
console.log('');

// Check for Discord IPC pipes on Windows
console.log('Checking for Discord IPC pipes...');

try {
  const pipes = execSync('powershell -Command "Get-ChildItem \\\\.\\pipe\\ | Where-Object {$_.Name -like \'discord-ipc-*\'}"', { encoding: 'utf-8' });
  if (pipes.trim()) {
    console.log('✓ Discord IPC pipes found:');
    console.log(pipes);
  } else {
    console.log('✗ No Discord IPC pipes found');
    console.log('This means Discord is not running or IPC is not initialized');
  }
} catch (error) {
  console.log('Could not check for IPC pipes:', error.message);
}

console.log('');
console.log('Attempting RPC connection...');

const rpc = new DiscordRPC.Client({ transport: 'ipc' });

rpc.on('ready', () => {
  console.log('✓ SUCCESS! Connected to Discord');
  console.log('User:', rpc.user.username + '#' + rpc.user.discriminator);
  console.log('');
  
  rpc.setActivity({
    details: 'Testing RPC',
    state: 'Connection Test',
    startTimestamp: Date.now(),
  }).then(() => {
    console.log('✓ Rich Presence set successfully!');
    console.log('Check your Discord profile - you should see the activity');
    console.log('');
    console.log('Disconnecting in 5 seconds...');
    setTimeout(() => {
      rpc.destroy();
      process.exit(0);
    }, 5000);
  }).catch(err => {
    console.error('✗ Failed to set activity:', err);
    process.exit(1);
  });
});

rpc.on('disconnected', () => {
  console.log('Disconnected from Discord');
});

// Set a timeout
const timeout = setTimeout(() => {
  console.log('');
  console.log('✗ TIMEOUT: Could not connect to Discord after 10 seconds');
  console.log('');
  console.log('Troubleshooting:');
  console.log('1. Is Discord desktop app running? (Check system tray)');
  console.log('2. Try fully closing Discord and reopening it');
  console.log('3. Check Discord Settings → Activity Privacy → "Display current activity" is enabled');
  console.log('4. Try running Discord as Administrator');
  console.log('5. Check if antivirus/firewall is blocking IPC communication');
  process.exit(1);
}, 10000);

rpc.login({ clientId }).catch(error => {
  clearTimeout(timeout);
  console.log('');
  console.log('✗ Connection failed with error:');
  console.log(error);
  process.exit(1);
});
