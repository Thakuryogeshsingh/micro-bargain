from django.contrib.admin.views.decorators import staff_member_required
from django.http import Http404, HttpResponse
from django.shortcuts import render
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.categories.models import Category
from apps.subscriptions.models import Plan
from apps.subscriptions.services import current_plan
from common.exceptions import BusinessRuleError
from common.permissions import IsMerchant, IsPlatformAdmin

from . import services
from .serializers import MerchantSalesQuerySerializer, ReportFilterSerializer

REPORTS = ("dashboard", "merchants", "customers", "deals")
XLSX = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"


def _filters(params):
    query = ReportFilterSerializer(data=params)
    query.is_valid(raise_exception=True)
    data = dict(query.validated_data)
    return services.Filters(**{k: v for k, v in data.items() if k != "export"}), data["export"]


def _excel_response(kind, f):
    response = HttpResponse(services.to_excel(services.report_sheets(kind, f)), content_type=XLSX)
    response["Content-Disposition"] = f'attachment; filename="{kind}_{f.date_from}_{f.date_to}.xlsx"'
    return response


# ---------- API (admin app / merchant app) ----------

class ReportView(APIView):
    """GET /analytics/{dashboard|merchants|customers|deals}/?date_from&date_to&city&category&export=xlsx"""

    permission_classes = [IsPlatformAdmin]
    kind = None

    @extend_schema(parameters=[ReportFilterSerializer], responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        f, fmt = _filters(request.query_params)
        if fmt == "xlsx":
            return _excel_response(self.kind, f)
        report = {
            "dashboard": services.dashboard, "merchants": services.merchant_report,
            "customers": services.customer_report, "deals": services.deal_report,
        }[self.kind](f)
        return Response(report)


class MerchantSalesView(APIView):
    permission_classes = [IsMerchant]

    @extend_schema(parameters=[MerchantSalesQuerySerializer], responses={200: OpenApiTypes.OBJECT})
    def get(self, request):
        if current_plan(request.user.merchant_profile).analytics == Plan.Analytics.BASIC:
            raise BusinessRuleError("Sales analytics are part of the Basic and Premium plans.", "upgrade_required")
        query = MerchantSalesQuerySerializer(data=request.query_params)
        query.is_valid(raise_exception=True)
        return Response(services.merchant_sales(request.user, query.validated_data["days"]))


# ---------- Django admin pages ----------

def _admin_filters(params):
    """Bad filter values in the admin form fall back to the defaults instead of an error page."""
    try:
        return _filters(params)[0]
    except ValidationError:
        return services.Filters()


@staff_member_required
def admin_dashboard(request):
    f = _admin_filters(request.GET)
    context = {
        "title": "Business dashboard",
        "metrics": services.dashboard(f),
        "deals": services.deal_report(f, top=5),
        "customers": services.customer_report(f),
        "filters": f,
        "categories": Category.objects.filter(is_active=True),
        "query": request.GET.urlencode(),
        "reports": REPORTS,
    }
    return render(request, "admin/analytics/dashboard.html", context)


@staff_member_required
def admin_report_download(request, kind):
    if kind not in REPORTS:
        raise Http404
    f = _admin_filters(request.GET)
    return _excel_response(kind, f)
