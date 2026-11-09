import axios from 'axios'

export default ({ req }) => {
  if (typeof window === 'undefined') {
    // We are on the server
    // Lab 2: cho phép cấu hình URL nội bộ cluster qua biến môi trường
    // SERVER_BASE_URL (vd: http://traefik.kube-system.svc.cluster.local trên k3s)
    const fallback = process.env.NODE_ENV === 'production'
      ? 'https://www.aurapan.com'
      : 'http://ingress-nginx-controller.ingress-nginx.svc.cluster.local'

    return axios.create({
      baseURL: process.env.SERVER_BASE_URL || fallback,
      headers: req.headers,
      withCredentials: true
    })
  } else {
    // We must be on the browser
    return axios.create({
      baseUrl: '/'
    })
  }
}
