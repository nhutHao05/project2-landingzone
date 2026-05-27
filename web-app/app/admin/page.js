'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';

export default function AdminDashboard() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  
  // Form State
  const [isEditing, setIsEditing] = useState(false);
  const [currentId, setCurrentId] = useState(null);
  const [formData, setFormData] = useState({ name: '', description: '', price: '', image_emoji: '📦' });

  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    try {
      const res = await fetch('/api/products');
      const data = await res.json();
      if (!data.error) setProducts(data.products || []);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const url = isEditing ? `/api/products/${currentId}` : '/api/products';
    const method = isEditing ? 'PUT' : 'POST';

    try {
      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });
      const data = await res.json();
      
      if (data.success) {
        resetForm();
        fetchProducts();
      } else {
        alert(data.error);
      }
    } catch (err) {
      alert(err.message);
    }
  };

  const handleEdit = (product) => {
    setIsEditing(true);
    setCurrentId(product.id);
    setFormData({
      name: product.name,
      description: product.description,
      price: product.price,
      image_emoji: product.image_emoji
    });
  };

  const handleDelete = async (id) => {
    if (!confirm('Are you sure you want to delete this product?')) return;
    try {
      const res = await fetch(`/api/products/${id}`, { method: 'DELETE' });
      const data = await res.json();
      if (data.success) fetchProducts();
    } catch (err) {
      alert(err.message);
    }
  };

  const resetForm = () => {
    setIsEditing(false);
    setCurrentId(null);
    setFormData({ name: '', description: '', price: '', image_emoji: '📦' });
  };

  return (
    <>
      <div className="ambient-bg"></div>
      <nav className="navbar">
        <div className="logo">CyberMart Admin</div>
        <Link href="/" className="cart-btn">⬅ Back to Store</Link>
      </nav>
      
      <main className="admin-main">
        <h1 style={{ marginTop: '5rem', marginBottom: '2rem' }}>Product Management (CRUD)</h1>
        
        <div className="admin-container">
          {/* Create / Update Form */}
          <section className="admin-form-section">
            <h2>{isEditing ? 'Edit Product' : 'Add New Product'}</h2>
            <form onSubmit={handleSubmit} className="admin-form">
              <div className="form-group">
                <label>Product Name</label>
                <input type="text" name="name" value={formData.name} onChange={handleInputChange} required />
              </div>
              <div className="form-group">
                <label>Price ($)</label>
                <input type="number" step="0.01" name="price" value={formData.price} onChange={handleInputChange} required />
              </div>
              <div className="form-group">
                <label>Emoji Icon</label>
                <input type="text" name="image_emoji" value={formData.image_emoji} onChange={handleInputChange} />
              </div>
              <div className="form-group">
                <label>Description</label>
                <textarea name="description" value={formData.description} onChange={handleInputChange} rows="3"></textarea>
              </div>
              
              <div className="form-actions">
                <button type="submit" className="btn-primary">{isEditing ? 'Update Product' : 'Create Product'}</button>
                {isEditing && <button type="button" onClick={resetForm} className="btn-secondary">Cancel</button>}
              </div>
            </form>
          </section>

          {/* Read / Delete Table */}
          <section className="admin-table-section">
            <h2>Current Inventory</h2>
            {loading ? <p>Loading...</p> : (
              <div className="table-responsive">
                <table className="admin-table">
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Icon</th>
                      <th>Name</th>
                      <th>Price</th>
                      <th>Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {products.map(p => (
                      <tr key={p.id}>
                        <td>{p.id}</td>
                        <td style={{fontSize: '1.5rem'}}>{p.image_emoji}</td>
                        <td>{p.name}</td>
                        <td>${Number(p.price).toFixed(2)}</td>
                        <td>
                          <button onClick={() => handleEdit(p)} className="btn-edit">Edit</button>
                          <button onClick={() => handleDelete(p.id)} className="btn-delete">Delete</button>
                        </td>
                      </tr>
                    ))}
                    {products.length === 0 && (
                      <tr><td colSpan="5" style={{textAlign: 'center'}}>No products found.</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
            )}
          </section>
        </div>
      </main>
    </>
  );
}
