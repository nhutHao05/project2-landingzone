import './globals.css';

export const metadata = {
  title: 'CyberMart | Premium Tech Store',
  description: 'The best place to buy premium cyber gear.',
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
