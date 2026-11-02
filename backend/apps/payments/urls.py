from django.urls import path

from . import views

app_name = "payments"

urlpatterns = [
    path("create/", views.PaymentCreateView.as_view(), name="create"),
    path("verify/", views.PaymentVerifyView.as_view(), name="verify"),
    path("webhook/", views.PaymentWebhookView.as_view(), name="webhook"),
    path("dev-complete/", views.DevCompletePaymentView.as_view(), name="dev-complete"),
    path("history/", views.PaymentHistoryView.as_view(), name="history"),
    path("<int:pk>/", views.PaymentDetailView.as_view(), name="detail"),
]
