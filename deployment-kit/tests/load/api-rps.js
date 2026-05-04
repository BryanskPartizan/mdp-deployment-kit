import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  scenarios: {
    api_load: {
      executor: 'ramping-vus',
      stages: [
        { duration: '30s', target: 10 },
        { duration: '60s', target: 40 },
        { duration: '30s', target: 0 },
      ],
    },
  },
};

const domain = __ENV.APP_DOMAIN || 'pkhco.ru';
const target = __ENV.TARGET_URL || `https://api.${domain}/health`;

export default function () {
  const res = http.get(target);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
